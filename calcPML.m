function PML = calcPML(SPMP)
%CALCPML Calculate password management level from SPMP controls.

weights = dictionary();
weights("RAL") = 0.41;
weights("mPA") = 0.611;
weights("ALD") = 0.611;
weights("MPA") = 0.745;
weights("EPH") = 0.849;
weights("ALT") = 1.11;
weights("MPL") = 1.161;
weights("PCR") = 2.07;
weights("SPE") = 2.414;

PML = 0;
weightKeys = keys(weights);
for i = 1:numel(weightKeys)
    key = weightKeys(i);
    if isConfigured(SPMP, key)
        PML = PML + SPMP(key) * weights(key);
    end
end
end

function configured = isConfigured(SPMP, key)
try
    configured = isKey(SPMP, key);
catch
    configured = any(keys(SPMP) == key);
end
end
