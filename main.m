import matlab.net.*
import matlab.net.http.*

r = RequestMessage;
base_url = "https://services.nvd.nist.gov/rest/json/cpes/2.0";
parameter_name = "keywordSearch";
parameter_value = "notepad";
uri = URI(base_url + "?" + parameter_name + "=" + parameter_value);

resp = send(r, uri);
disp(resp.StatusCode);
