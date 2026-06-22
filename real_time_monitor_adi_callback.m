function real_time_monitor_adi_callback(transaction)
%REAL_TIME_MONITOR_ADI_CALLBACK Stable top-level WebSocket callback.
% Timer callbacks on Linux can fail to resolve anonymous handles that close
% over local functions in real_time_monitor.m, so keep the handle resolvable.
real_time_monitor('adi_callback_transaction', transaction);
end
