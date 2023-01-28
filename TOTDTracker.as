
dictionary totdTracks;
void initTOTDProcessor() {
    NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURL()+"/api/token/campaign/month?offset=0&length="+Text::Format("%d", getTotalMonths()));
    req.Start();
    while (!req.Finished()) yield();
	Json::Value resp = Json::Parse(req.String());

    Json::Value months = resp["monthList"];
    for (uint i = 0; i < months.Length; i++) {
        uint year = months[i]["year"];
        uint month = months[i]["month"];
        for (int ii = 0; ii < months[i]["lastDay"]; ii++) {
            uint day = months[i]["days"][ii]["monthDay"];
            // string dayStr = Text::Format("%d", year) + "-" + Text::Format("%d", month) + "-" + Text::Format("%d", day);
            totdTracks.Set(months[i]["days"][ii]["mapUid"], months[i]["days"][ii]["startTimestamp"]);
        }
    }
}

/**
 * gets the total number of months we've had TOTDs (2020-07)
 */
uint getTotalMonths() {
    uint nowMt = Text::ParseUInt(Time::FormatString("%m", Time::Stamp));
    uint nowYr = Text::ParseUInt(Time::FormatString("%Y", Time::Stamp));
    return (nowMt + 6) + (nowYr - 2021)*12;
}
