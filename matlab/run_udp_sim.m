% Script to run the Simulink model for simulation
modelName = 'udp_sine_gen';

% Add current folder and utils to path
scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
addpath(scriptDir);
addpath(fullfile(projectRoot, 'utils'));

% Ensure 'bld' directory exists and is set as the cache folder
bldDir = fullfile(projectRoot, 'bld');
if ~exist(bldDir, 'dir')
    mkdir(bldDir);
end
Simulink.fileGenControl('set', 'CacheFolder', bldDir, 'CodeGenFolder', bldDir);

% Load the model if not already loaded
if ~bdIsLoaded(modelName)
    load_system(modelName);
end

% Read configuration
cfg = ConfigReader();
pacingRate = cfg.getValue('pacing_rate');

% 1. Create and configure the simulation object
sm = simulation(modelName);
sm = setModelParameter(sm, StopTime="inf");
sm = setModelParameter(sm, EnablePacing="on", PacingRate=num2str(pacingRate));

fprintf('Starting simulation of %s...\n', modelName);

% 2. Start the simulation (non-blocking)
sm.start();

% 3. Display control instructions
fprintf('\nSimulation Control Instructions:\n');
fprintf('  STOP:    type "sm.stop()" or use the Stop button in Simulink.\n');
fprintf('  PAUSE:   type "sm.pause()" or use the Pause button.\n');
fprintf('  RESUME:  type "sm.resume()" or use the Resume button.\n');
fprintf('  RESTART: stop first, then run "run_udp_sim" again.\n\n');
