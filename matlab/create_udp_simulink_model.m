% Script to create an improved Simulink model with a Digital Twin subsystem
modelName = 'udp_sine_gen';

% Get the directory where this script is located
matlabDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(matlabDir);
modelPath = fullfile(matlabDir, [modelName '.slx']);
serializerPath = fullfile(matlabDir, 'JSONSerializer.m');

% Add folders to path
addpath(matlabDir);
addpath(fullfile(projectRoot, 'utils'));

% Read configuration
cfg = ConfigReader();
sampleTime = cfg.getValue('sample_time');

% For Send blocks, use target_subscriber if available, fallback to address.
% In Docker, target_subscriber will be 'subscriber'.
if cfg.hasKey('target_subscriber')
    udpAddr = cfg.getValue('target_subscriber');
elseif cfg.hasKey('address')
    udpAddr = cfg.getValue('address');
else
    udpAddr = '127.0.0.1'; % Absolute fallback
end

% For Receive blocks, use bind_address (default 0.0.0.0) to listen on all interfaces.
% This is essential for receiving data from Docker or other network hosts.
if cfg.hasKey('bind_address')
    bindAddr = cfg.getValue('bind_address');
else
    bindAddr = '0.0.0.0';
end

recvPort = cfg.getValue('receiver_port');
sinkPort = cfg.getValue('sink_port');
controlPort = cfg.getValue('control_port');
bufferSize = cfg.getValue('json_buffer_size');
pacingRate = cfg.getValue('pacing_rate');

% 1. Clean up existing files and memory
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if exist(modelPath, 'file'), delete(modelPath); end
if exist(serializerPath, 'file'), delete(serializerPath); end

% 2. Create the JSONSerializer.m System Object
jsonClassContent = { ...
    'classdef JSONSerializer < matlab.System'
    ['    % JSONSerializer Formats input as JSON string with wall-clock timestamp (BufferSize: ' num2str(bufferSize) ')']
    '    properties (Access = private)'
    '        BaseTime = 0;'
    '    end'
    '    '
    '    methods(Access = protected)'
    '        function setupImpl(obj)'
    '            if coder.target(''MATLAB'')'
    '                obj.BaseTime = posixtime(datetime(''now''));'
    '            else'
    '                coder.cinclude(''<time.h>'');'
    '                t_base = coder.opaque(''time_t'', ''0'');'
    '                t_base = coder.ceval(''time'', coder.wref(t_base));'
    '                obj.BaseTime = double(t_base);'
    '            end'
    '        end'
    '        '
    '        function y = stepImpl(obj, t, v)'
    '            unixTime = double(obj.BaseTime) + double(t(1));'
    '            val = double(v(1));'
    '            str = sprintf(''{"timestamp": %.3f, "value": %.3f}'', unixTime, val);'
    ['            y = zeros(1, ' num2str(bufferSize) ', ''uint8'');']
    '            bytes = uint8(str);'
    ['            len = min(length(bytes), ' num2str(bufferSize) ');']
    '            y(1:len) = bytes(1:len);'
    '        end'
    '        '
    '        function out = getOutputSizeImpl(~)'
    ['            out = [1 ' num2str(bufferSize) '];']
    '        end'
    '        '
    '        function out = getOutputDataTypeImpl(~)'
    '            out = ''uint8'';'
    '        end'
    '        '
    '        function out = isOutputFixedSizeImpl(~)'
    '            out = true;'
    '        end'
    '        '
    '        function out = isOutputComplexImpl(~)'
    '            out = false;'
    '        end'
    '        '
    '        function out = isInputComplexImpl(~, ~)'
    '            out = false;'
    '        end'
    '        '
    '        function out = isInputSizeMutableImpl(~, ~)'
    '            out = true;'
    '        end'
    '    end'
    'end'
};

fid = fopen(serializerPath, 'w');
for i = 1:length(jsonClassContent), fprintf(fid, '%s\n', jsonClassContent{i}); end
fclose(fid);
rehash;

% 3. Create a new model
new_system(modelName); open_system(modelName);

% 4. Create Digital Twin Subsystem
subsystemName = [modelName '/Digital Twin'];
add_block('built-in/Subsystem', subsystemName, 'Position', [250, 100, 400, 200]);

% Inside the subsystem
add_block('built-in/Inport', [subsystemName '/SensorReading'], 'Position', [20, 30, 50, 45]);
add_block('built-in/Inport', [subsystemName '/SetPressure'], 'Position', [20, 80, 50, 95]);
add_block('built-in/Outport', [subsystemName '/Output'], 'Position', [300, 55, 330, 70]);

% Basic logic inside Digital Twin: SensorReading + SetPressure
add_block('simulink/Math Operations/Sum', [subsystemName '/Add'], 'Position', [150, 45, 180, 80]);
add_line(subsystemName, 'SensorReading/1', 'Add/1');
add_line(subsystemName, 'SetPressure/1', 'Add/2');
add_line(subsystemName, 'Add/1', 'Output/1');

% 5. Add UDP Receive block (Sensor Input from Python)
try
    add_block('dspnetwork/UDP Receive', [modelName '/UDP_Sensor'], ...
        'LocalPort', num2str(sinkPort), 'SampleTime', num2str(sampleTime), ...
        'DataSize', '1', 'OutputVariableSizeSignal', 'off', ...
        'Position', [50, 100, 150, 140]);
    % For newer dspnetwork blocks, if LocalIPAddress exists:
    try
        set_param([modelName '/UDP_Sensor'], 'LocalIPAddress', bindAddr);
    catch
    end
catch
    add_block('instrumentlib/UDP Receive', [modelName '/UDP_Sensor'], ...
        'LocalPort', num2str(sinkPort), 'DataSize', '1', 'DataType', 'double', ...
        'SampleTime', num2str(sampleTime), 'Position', [50, 100, 150, 140]);
    % Set correct mask parameters for Instrument Control Toolbox block
    set_param([modelName '/UDP_Sensor'], 'LocalAddress', bindAddr);
    set_param([modelName '/UDP_Sensor'], 'EnableBlockingMode', 'off');
    set_param([modelName '/UDP_Sensor'], 'ByteOrder', 'little-endian');
    set_param([modelName '/UDP_Sensor'], 'GetLatestData', 'on');
end

% 6. Add UDP Receive block (Set Pressure from Dashboard)
try
    add_block('dspnetwork/UDP Receive', [modelName '/UDP_SetPressure'], ...
        'LocalPort', num2str(controlPort), 'SampleTime', num2str(sampleTime), ...
        'DataSize', '1', 'OutputVariableSizeSignal', 'off', ...
        'Position', [50, 160, 150, 200]);
    try
        set_param([modelName '/UDP_SetPressure'], 'LocalIPAddress', bindAddr);
    catch
    end
catch
    add_block('instrumentlib/UDP Receive', [modelName '/UDP_SetPressure'], ...
        'LocalPort', num2str(controlPort), 'DataSize', '1', 'DataType', 'double', ...
        'SampleTime', num2str(sampleTime), 'Position', [50, 160, 150, 200]);
    set_param([modelName '/UDP_SetPressure'], 'LocalAddress', bindAddr);
    set_param([modelName '/UDP_SetPressure'], 'EnableBlockingMode', 'off');
    set_param([modelName '/UDP_SetPressure'], 'ByteOrder', 'little-endian');
    set_param([modelName '/UDP_SetPressure'], 'GetLatestData', 'on');
end

% 7. Add Timestamp source
add_block('simulink/Sources/Digital Clock', [modelName '/Clock'], ...
    'SampleTime', num2str(sampleTime), 'Position', [250, 40, 290, 60]);

% 8. Add JSON Formatter (MATLAB System Block)
add_block('simulink/User-Defined Functions/MATLAB System', [modelName '/JSONFormatter'], ...
    'System', 'JSONSerializer', 'Position', [450, 70, 550, 130]);

% 9. Add UDP Send block (Output)
try
    add_block('dspnetwork/UDP Send', [modelName '/UDPSend'], ...
        'RemoteAddress', udpAddr, 'RemotePort', num2str(recvPort), ...
        'Position', [600, 85, 680, 125]);
catch
    add_block('instrumentlib/UDP Send', [modelName '/UDPSend'], ...
        'Host', udpAddr, 'Port', num2str(recvPort), ...
        'Position', [600, 85, 680, 125]);
end

% 10. Connect the blocks
add_line(modelName, 'UDP_Sensor/1', 'Digital Twin/1');
add_line(modelName, 'UDP_SetPressure/1', 'Digital Twin/2');
add_line(modelName, 'Clock/1', 'JSONFormatter/1');
add_line(modelName, 'Digital Twin/1', 'JSONFormatter/2');
add_line(modelName, 'JSONFormatter/1', 'UDPSend/1');

% 11. Configure Simulation Parameters
set_param(modelName, 'Solver', 'FixedStepDiscrete');
set_param(modelName, 'FixedStep', num2str(sampleTime));
set_param(modelName, 'StopTime', 'inf');
set_param(modelName, 'EnablePacing', 'on');
set_param(modelName, 'PacingRate', num2str(pacingRate));

% 12. Save the model
save_system(modelName, modelPath);
fprintf('Model %s updated with Digital Twin subsystem and Set Pressure control.\n', modelName);
