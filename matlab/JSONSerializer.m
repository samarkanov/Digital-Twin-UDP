classdef JSONSerializer < matlab.System
    % JSONSerializer Formats input as JSON string with wall-clock timestamp (BufferSize: 128)
    properties (Access = private)
        BaseTime = 0;
    end
    
    methods(Access = protected)
        function setupImpl(obj)
            if coder.target('MATLAB')
                obj.BaseTime = posixtime(datetime('now'));
            else
                coder.cinclude('<time.h>');
                t_base = coder.opaque('time_t', '0');
                t_base = coder.ceval('time', coder.wref(t_base));
                obj.BaseTime = double(t_base);
            end
        end
        
        function y = stepImpl(obj, t, v)
            unixTime = double(obj.BaseTime) + double(t(1));
            val = double(v(1));
            str = sprintf('{"timestamp": %.3f, "value": %.3f}', unixTime, val);
            y = zeros(1, 128, 'uint8');
            bytes = uint8(str);
            len = min(length(bytes), 128);
            y(1:len) = bytes(1:len);
        end
        
        function out = getOutputSizeImpl(~)
            out = [1 128];
        end
        
        function out = getOutputDataTypeImpl(~)
            out = 'uint8';
        end
        
        function out = isOutputFixedSizeImpl(~)
            out = true;
        end
        
        function out = isOutputComplexImpl(~)
            out = false;
        end
        
        function out = isInputComplexImpl(~, ~)
            out = false;
        end
        
        function out = isInputSizeMutableImpl(~, ~)
            out = true;
        end
    end
end
