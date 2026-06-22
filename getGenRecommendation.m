function recommendation = getGenRecommendation(risk)
%GET Summary of this function goes here
%   Detailed explanation goes here
if risk>=0.8
    recommendation="Risk level is VERY HIGH. Check access policy, stop activity";
else
    if risk>=0.6
        recommendation="Risk level is HIGH. Access policy need immediate correction";
    else
        if risk >=0.4
            recommendation="Risk level is SUBSTANTIAL. Access policy required correction";
        else
            if risk>=0.2
                recommendation="Risk level is POSSIBLE. Access policy need attention";
            else
                recommendation="Risk level is SLIGHT. Access policy acceptable";
            end
        end
    end
end

end

