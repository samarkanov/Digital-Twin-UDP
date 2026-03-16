classdef ConfigReader < handle
    % ConfigReader: utility to read project configuration from TOML
    
    properties (Access = private)
        ConfigMap
    end
    
    methods
        function obj = ConfigReader(configFilePath)
            % Constructor: reads the TOML file into an internal map
            obj.ConfigMap = containers.Map();
            
            if nargin < 1
                % Default to config.toml in project root (one level up from utils)
                utilsDir = fileparts(mfilename('fullpath'));
                configFilePath = fullfile(fileparts(utilsDir), 'config.toml');
            end
            
            if ~exist(configFilePath, 'file')
                error('Config file not found: %s', configFilePath);
            end
            
            obj.parseFile(configFilePath);
        end
        
        function val = getLibraryPath(obj)
            % Check environment variable first
            envPath = getenv('MATLAB_PATH');
            if ~isempty(envPath)
                val = fullfile(envPath, 'glnxa64');
                fprintf('Using MATLAB_PATH from environment: %s\n', val);
                return;
            end
            
            % Fallback to config file
            val = obj.getValue('library_path');
        end
        
        function val = getValue(obj, key)
            % Generic getter for any key
            if isKey(obj.ConfigMap, key)
                val = obj.ConfigMap(key);
            else
                error('Key "%s" not found in config.', key);
            end
        end
        
        function res = hasKey(obj, key)
            res = isKey(obj.ConfigMap, key);
        end
    end
    
    methods (Access = private)
        function parseFile(obj, filePath)
            fid = fopen(filePath, 'r');
            if fid == -1
                error('Could not open config file: %s', filePath);
            end
            
            % Clean up on exit
            cleanup = onCleanup(@() fclose(fid));
            
            currentSection = '';
            
            while ~feof(fid)
                line = strtrim(fgetl(fid));
                
                % Ignore empty lines and comments
                if isempty(line) || startsWith(line, '#')
                    continue;
                end
                
                % Match section header [section]
                sectionToken = regexp(line, '^\[([a-zA-Z0-9_]+)\]$', 'tokens');
                if ~isempty(sectionToken)
                    currentSection = sectionToken{1}{1};
                    continue;
                end
                
                % Match key = "string" or key = 'string'
                strTokens = regexp(line, '^([a-zA-Z0-9_]+)\s*=\s*["''](.*)["''](\s*#.*)?$', 'tokens');
                if ~isempty(strTokens)
                    key = strTokens{1}{1};
                    val = strTokens{1}{2};
                    obj.ConfigMap(key) = val;
                    continue;
                end
                
                % Match key = numeric
                numTokens = regexp(line, '^([a-zA-Z0-9_]+)\s*=\s*([0-9\.\-]+)(\s*#.*)?$', 'tokens');
                if ~isempty(numTokens)
                    key = numTokens{1}{1};
                    val = str2double(numTokens{1}{2});
                    obj.ConfigMap(key) = val;
                    continue;
                end
            end
        end
    end
end
