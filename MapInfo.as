

void Main() {
	init();
	while (true) {
		step();
		yield();
	}
}

void Render() {
	if (!showMapInfo) return;
	if (GetApp().CurrentPlayground is null || GetApp().RootMap is null || GetApp().Editor !is null) return;

	// @todo: maybe do this with nvg instead?
	if (UI::Begin("\\$8f0" + Icons::Map + "\\$z Map Info", UI::WindowFlags::AlwaysAutoResize)) {

		// shitty debug view for now
		UI::BeginTable("mapInfoDebug", 2);

		string[] keys = mapInfo.GetKeys();
		for (uint i = 0; i < keys.Length; i++) {
			UI::TableNextRow();
			UI::TableNextColumn();
			UI::Text(keys[i]);
			UI::TableNextColumn();
			UI::Text(string(mapInfo[keys[i]]));
		}

		UI::EndTable();
	}
	UI::End();
}

void RenderMenu() {
	if(UI::MenuItem("\\$8f0" + Icons::Map + "\\$z Map Info", "", showMapInfo)) {
		showMapInfo = !showMapInfo;
	}
}

void OnSettingsChanged() {
    init();
}

void init() {
	startnew(initTOTDProcessor);
}

dictionary mapInfo;
string currentMapUid;
void step() {
	CTrackMania@ app = cast<CTrackMania>(GetApp());
	if (app.CurrentPlayground is null || app.RootMap is null || app.Editor !is null) return;
	CGameCtnChallenge@ map = app.RootMap;
	string mapUid = map.MapInfo.MapUid;

	if(mapUid != currentMapUid) {
		onNewMap(map);
		currentMapUid = mapUid;
	}



}

void onNewMap(CGameCtnChallenge@ map) {
	getNadeoMapData(map.MapInfo.MapUid);
	mapInfo.Set("Map UID", map.MapInfo.MapUid);
	mapInfo.Set("Name", string(map.MapInfo.Name));
	mapInfo.Set("Author nick", string(map.MapInfo.AuthorNickName));
	mapInfo.Set("Author login", map.MapInfo.AuthorLogin);

	if (isOnNadeoServices) {
		mapInfo.Set("Uploaded", Time::FormatString("%c", nadeoData["uploadTimestamp"]));
	}

	if (totdTracks.Exists(map.MapInfo.MapUid)) {
		mapInfo.Set("TOTD on", Time::FormatString("%c", uint64(totdTracks[map.MapInfo.MapUid])));
	} else {
		mapInfo.Set("TOTD on", "n/a");
	}
	
}

bool isOnNadeoServices = false;
Json::Value nadeoData;

void getNadeoMapData(const string &in uid) {
	NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURL()+"/api/token/map/"+uid);
	req.Start();
    while (!req.Finished()) yield();
	Json::Value resp = Json::Parse(req.String());
	isOnNadeoServices = (resp.GetType() == Json::Type::Object);
	nadeoData = resp;
}
