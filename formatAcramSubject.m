function subjectName = formatAcramSubject(objectName)
%FORMATACRAMSUBJECT Return ADI subject in the agreed ip_src/name_src form.
    subject = string(objectName);
    if isempty(subject)
        subjectName = objectName;
        return;
    end
    subject = strtrim(subject(1));

    aliases = [
        "WAN_Router", "ip_src=192.168.1.1;name_src=WAN_Router";
        "WAN Gateway", "ip_src=192.168.1.1;name_src=WAN_Router";
        "Server-2", "ip_src=192.168.1.21;name_src=Server-2";
        "Server-1", "ip_src=192.168.1.25;name_src=Server-1";
        "SmartPlug_Server-2", "ip_src=192.168.1.100;name_src=SmartPlug_Server-2";
        "Smart Plugs 192.168.1.100", "ip_src=192.168.1.100;name_src=SmartPlug_Server-2";
        "Wifi_AP", "ip_src=192.168.1.101;name_src=Wifi_AP";
        "Smart Plugs 192.168.1.103", "ip_src=192.168.1.103;name_src=SmartPlug_MLBoard";
        "SmartPlug_MLBoard", "ip_src=192.168.1.103;name_src=SmartPlug_MLBoard";
        "Smart Plugs 192.168.1.104", "ip_src=192.168.1.104;name_src=SmartPlug_IPCamera";
        "SmartPlug_IPCamera", "ip_src=192.168.1.104;name_src=SmartPlug_IPCamera";
        "Smart Plugs 192.168.1.107", "ip_src=192.168.1.107;name_src=SmartPlug_Router";
        "SmartPlug_Router", "ip_src=192.168.1.107;name_src=SmartPlug_Router";
        "Smart Plugs 192.168.1.108", "ip_src=192.168.1.108;name_src=SmartPlug_Server-1";
        "SmartPlug_Server-1", "ip_src=192.168.1.108;name_src=SmartPlug_Server-1";
        "Smart Plugs 192.168.1.109", "ip_src=192.168.1.109;name_src=SmartPlug_RaspPI";
        "SmartPlug_RaspPI", "ip_src=192.168.1.109;name_src=SmartPlug_RaspPI";
        "Smart Plugs 192.168.1.113", "ip_src=192.168.1.113;name_src=SmartPlug_Robot";
        "SmartPlug_Robot", "ip_src=192.168.1.113;name_src=SmartPlug_Robot";
        "Router", "ip_src=192.168.1.110;name_src=SmartSwitch";
        "SmartSwitch", "ip_src=192.168.1.110;name_src=SmartSwitch";
        "WiFi AP", "ip_src=192.168.1.101;name_src=Wifi_AP";
        "Ubiquity WiFi", "ip_src=192.168.1.101;name_src=Wifi_AP";
        "IP Camera", "ip_src=192.168.1.252;name_src=IP_Camera";
        "IP_Camera", "ip_src=192.168.1.252;name_src=IP_Camera";
        "Machine Learning Board", "ip_src=192.168.1.250;name_src=ML_Board";
        "Google ML Board", "ip_src=192.168.1.250;name_src=ML_Board";
        "ML_Board", "ip_src=192.168.1.250;name_src=ML_Board";
        "Robot", "ip_src=192.168.1.150;name_src=Robot";
        "OpenVPN (On Server-2)", "ip_src=192.168.1.232;name_src=VM_OpenVPN_Server";
        "VM_OpenVPN_Server", "ip_src=192.168.1.232;name_src=VM_OpenVPN_Server";
        "RaspberryPi", "ip_src=192.168.1.251;name_src=RaspberryPI";
        "RaspberryPI", "ip_src=192.168.1.251;name_src=RaspberryPI";
        "Robot-MES (On Server-1)", "ip_src=192.168.1.242;name_src=VM_Robot-MES";
        "VM_Robot-MES", "ip_src=192.168.1.242;name_src=VM_Robot-MES";
        "Telemetry2 (On Server-2)", "ip_src=192.168.1.243;name_src=VM_Telemetry2";
        "VM_Telemetry2", "ip_src=192.168.1.243;name_src=VM_Telemetry2";
        "UC-1 (On Server-1)", "ip_src=192.168.1.238;name_src=VM_UC2-1";
        "VM_UC2-1", "ip_src=192.168.1.238;name_src=VM_UC2-1";
        "UC-2 (On Server-1)", "ip_src=192.168.1.236;name_src=VM_UC2-2";
        "VM_UC2-2", "ip_src=192.168.1.236;name_src=VM_UC2-2";
        "UC-3 (On Server-1)", "ip_src=192.168.1.237;name_src=VM_UC2-3";
        "VM_UC2-3", "ip_src=192.168.1.237;name_src=VM_UC2-3"
    ];

    if contains(subject, "ip_src=") && contains(subject, ";name_src=")
        subjectName = normalizeByIp(subject, aliases);
        return;
    end

    for i = 1:size(aliases, 1)
        if strcmpi(subject, aliases(i, 1))
            subjectName = char(aliases(i, 2));
            return;
        end
    end

    subjectName = char(subject);
end

function subjectName = normalizeByIp(subject, aliases)
    tokIp = regexp(char(subject), 'ip_src=([^;]+)', 'tokens', 'once');
    if isempty(tokIp)
        subjectName = char(subject);
        return;
    end

    ip = string(strtrim(tokIp{1}));
    for i = 1:size(aliases, 1)
        tokKnownIp = regexp(char(aliases(i, 2)), 'ip_src=([^;]+)', 'tokens', 'once');
        if ~isempty(tokKnownIp) && ip == string(tokKnownIp{1})
            subjectName = char(aliases(i, 2));
            return;
        end
    end

    subjectName = char(subject);
end
