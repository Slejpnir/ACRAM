function websocket_receiver(wsURL, handleTxnFcn)
%WEBSOCKET_RECEIVER  Opens a WebSocket and pushes every JSON message
%                    to the user-supplied callback.
%
%   websocket_receiver("ws://host:port/stream", @myFcn)
%
% Inputs
%   wsURL         – Full ws:// or wss:// URL
%   handleTxnFcn  – function_handle that accepts one MATLAB struct
%
% Example
%   websocket_receiver("ws://localhost:5050/tx", @(t)disp(t))

arguments
    wsURL           (1,1) string
    handleTxnFcn    (1,1) function_handle = @(txn)disp(txn)
end

% ---- open connection ---------------------------------------------------
ws = websocket(wsURL);

configureCallback(ws, "open",  @(~,~)fprintf("✅  WebSocket open → %s\n", wsURL));
configureCallback(ws, "close", @(~,~)fprintf("❎  WebSocket closed\n"));
configureCallback(ws, "error", @(~,ev) fprintf(2,"⚠️  WS error: %s\n", ev.Error));

configureCallback(ws, "message", @(src,~)onMessage(src, handleTxnFcn));

disp("Press Ctrl-C to stop.");
while strcmp(ws.Status, "open")
    pause(0.1);           % cooperative wait so Ctrl-C works
end
end

% ------------------------------------------------------------------------
function onMessage(ws, handleTxnFcn)
    raw = read(ws);                 % uint8
    txt = string(char(raw));        % UTF-8 → char → string
    try
        txn = jsondecode(txt);
        handleTxnFcn(txn);          % hand off to user logic
    catch ME
        warning("Skipping bad payload (%s): %s", warning(E.identifier,"%s",E.message), txt);
    end
end