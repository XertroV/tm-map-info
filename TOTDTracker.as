
dictionary totdTracks;
void initTOTDProcessor() {
    NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURL()+"/api/token/campaign/month?offset=0&length="+Text::Format("%d", getTotalMonths()));
    req.Start();
    while (!req.Finished()) yield();
	Json::Value resp = Json::Parse(req.String());

}

/**
 * gets the total number of months we've had TOTDs (2020-07)
 */
uint getTotalMonths() {
    uint nowMt = Text::ParseUInt(Time::FormatString("%m", Time::Stamp));
    uint nowYr = Text::ParseUInt(Time::FormatString("%Y", Time::Stamp));
    return (nowMt + 6) + (nowYr - 2021)*12;
}
