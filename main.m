import matlab.net.*
import matlab.net.http.*
api_key="5c597a2b-2ead-4142-b70c-9541228534bb";
r = RequestMessage;
base_url="https://services.nvd.nist.gov/rest/json/cpes/2.0";
parameter_name="keywordSearch";
parameter_value="notepad";
uri = URI(base_url+"?"+parameter_name+"="+parameter_value);

resp = send(r,uri);
status = resp.StatusCode
