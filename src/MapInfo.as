
void DrawMapInfoUI() {
	if (!S_ShowMapInfo) return;
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



dictionary mapInfo;
string currentMapUid;

MapInfo_UI@ g_MapInfo = null;

void step() {
	CTrackMania@ app = cast<CTrackMania>(GetApp());
	string mapUid;
	if (app.CurrentPlayground is null || app.RootMap is null || app.Editor !is null) {
		mapUid = "";
	} else {
		mapUid = app.RootMap.MapInfo.MapUid;
	}

	if(mapUid != currentMapUid) {
		currentMapUid = mapUid;
		onNewMap();
	}
}



void onNewMap() {
	if (currentMapUid.Length == 0) {
		@g_MapInfo = null;
		return;
	} else {
		@g_MapInfo = MapInfo_UI();
	}
	CGameCtnChallenge@ map = GetApp().RootMap;
	if (map is null) return;

	mapInfo.DeleteAll();
	getNadeoMapData(map.MapInfo.MapUid);
	mapInfo.Set("Map UID", map.MapInfo.MapUid);
	mapInfo.Set("Name", string(map.MapInfo.Name));
	mapInfo.Set("Author nick", string(map.MapInfo.AuthorNickName));
	mapInfo.Set("Author login", map.MapInfo.AuthorLogin);

	if (isOnNadeoServices) {
		mapInfo.Set("Uploaded", Time::FormatString("%c", nadeoData["uploadTimestamp"]));
	}

	// if (totdTracks.Exists(map.MapInfo.MapUid)) {
	// 	mapInfo.Set("TOTD on", Time::FormatString("%c", uint64(totdTracks[map.MapInfo.MapUid])));
	// } else {
	// 	mapInfo.Set("TOTD on", "n/a");
	// }
}

bool isOnNadeoServices = false;
Json::Value@ nadeoData;

void getNadeoMapData(const string &in uid) {
	NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURL()+"/api/token/map/"+uid);
	req.Start();
    while (!req.Finished()) yield();
	Json::Value resp = Json::Parse(req.String());
	isOnNadeoServices = (resp.GetType() == Json::Type::Object);
	@nadeoData = resp;
}


const uint LoadingNbPlayersFlag = 987654321;


/**
 * Class to manage getting map data from API sources. Intended as a base class for MapInfo_UI which handles drawing the info to the screen.
 */
class MapInfo_Data {
	string uid;
	string author;
	string Name;

	string AuthorAccountId = "";
	string AuthorDisplayName = "";
	string AuthorWebServicesUserId = "";
	string FileName = "";
	string FileUrl = "";
	string ThumbnailUrl = "";
	uint TimeStamp = 0;
	uint AuthorScore = 0;
	uint GoldScore = 0;
	uint SilverScore = 0;
	uint BronzeScore = 0;
	string DateStr = "";

	uint NbPlayers = LoadingNbPlayersFlag;
	uint WorstTime = 0;
	string NbPlayersStr = "";
	string WorstTimeStr = "";

	string TOTDDate = "";

	bool LoadedMapData = false;
	bool LoadedNbPlayers = false;
	bool LoadedWasTOTD = false;

	MapInfo_Data() {
		auto map = GetApp().RootMap;
		if (map is null) throw("Cannot instantiate MapInfo_Data when RootMap is null.");
		uid = map.EdChallengeId;
		Name = ColoredString(map.MapName);
		author = map.AuthorNickName;
		startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
		startnew(CoroutineFunc(this.GetMapInfoFromMapMonitorAPI));
		startnew(CoroutineFunc(this.GetMapTOTDStatus));
	}

	void GetMapInfoFromCoreAPI() {
		// This should usually be near-instant b/c the game has probably already loaded this.
		auto info = Core::GetMapFromUid(uid);
		if (info is null) return;
		AuthorAccountId = info.AuthorAccountId;
		AuthorDisplayName = info.AuthorDisplayName;
		AuthorWebServicesUserId = info.AuthorWebServicesUserId;

		Name = ColoredString(info.Name);
		FileName = info.FileName;
		FileUrl = info.FileUrl;
		ThumbnailUrl = info.ThumbnailUrl;
		TimeStamp = info.TimeStamp;
		DateStr = FmtTimestamp(TimeStamp);

		AuthorScore = info.AuthorScore;
		GoldScore = info.GoldScore;
		SilverScore = info.SilverScore;
		BronzeScore = info.BronzeScore;

		LoadedMapData = true;
		trace('MapInfo_Data loaded map data');
	}

	void GetMapInfoFromMapMonitorAPI() {
		auto resp = MapMonitor::GetNbPlayersForMap(uid);
		NbPlayers = resp.Get('nb_players', 98765);
		WorstTime = resp.Get('last_highest_score', 0);

		NbPlayersStr = NbPlayers % 1000 == 0 ? tostring(NbPlayers / 1000) + " K" : tostring(NbPlayers);
		WorstTimeStr = Time::Format(WorstTime);

		LoadedNbPlayers = true;
		trace('MapInfo_Data loaded nb players');
	}

	void GetMapTOTDStatus() {
		TOTDDate = TOTD::GetDateMapWasTOTD_Async(uid);
		LoadedWasTOTD = true;
	}
}

/**
 * Class extension to draw map info to screen
 */
class MapInfo_UI : MapInfo_Data {
	MapInfo_UI() {
		super();
	}

	vec2 baseRes = vec2(2560.0, 1440.0);
	float heightProp = 64.0 / baseRes.y;
	float fontProp = 40.0 / baseRes.y;
	float xPaddingProp = 20.0 / baseRes.y;
	// offset from middle of screen
	float topRightYOffs = (480.0 - baseRes.y / 2.0) / baseRes.y;
	float topRightXOffs = - (1720.0 - 840.0) / baseRes.x;
	vec2 trOffs = vec2(topRightXOffs, topRightYOffs);
	vec2 screen = baseRes;

	vec4 bounds = vec4(-10);
	vec4 UpdateBounds() {
		screen = vec2(Draw::GetWidth(), Draw::GetHeight());
		vec2 midPoint = screen / 2.0;
		float screenScale = screen.y / baseRes.y;
		vec2 tr = midPoint + (trOffs * baseRes) * screenScale;
		bounds.x = tr.x;
		bounds.y = tr.y;
		bounds.z = 0;
		bounds.w = heightProp * screen.y;
		return bounds;
	}

	void Draw() {
		if (!UI::IsGameUIVisible()) return;
		auto rect = UpdateBounds();

		nvg::Reset();

		nvg::FontFace(g_NvgFont);
		nvg::FontSize(fontProp * screen.y);
		nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

		string mainLabel = Icons::Users + " " + NbPlayersStr;

		auto textSize = nvg::TextBounds(mainLabel);
		float xPad = xPaddingProp * screen.y;

		float width = xPad * 2.0 + textSize.x;
		rect.x -= width;
		rect.z = width;

		nvg::BeginPath();
		nvg::Rect(rect.xy, rect.zw);
		nvg::FillColor(vec4(0, 0, 0, .8));
		nvg::Fill();

		nvg::FillColor(vec4(1.0));
		nvg::Text(rect.xy + rect.zw * vec2(.5, .55), mainLabel);

		nvg::ClosePath();
	}



	void Draw_DebugUI() {
		if (!S_ShowMapInfo) return;

		if (UI::Begin("\\$8f0" + Icons::Map + "\\$z Map Info " + uid, UI::WindowFlags::AlwaysAutoResize)) {

			// shitty debug view for now
			UI::BeginTable("mapInfoDebug", 2);

			DebugUITableRow("Name:", Name);
			DebugUITableRow("Author:", AuthorDisplayName);
			DebugUITableRow("Author WSID:", AuthorWebServicesUserId);
			DebugUITableRow("Author AcctID:", AuthorAccountId);
			DebugUITableRow("Published:", DateStr);
			DebugUITableRow("TOTD:", TOTDDate.Length > 0 ? TOTDDate : "--");
			DebugUITableRow("Nb Players:", NbPlayersStr);
			DebugUITableRow("Worst Time:", WorstTimeStr);

			UI::EndTable();
		}
		UI::End();
	}

	void DebugUITableRow(const string &in key, const string &in value) {
		UI::TableNextRow();
		UI::TableNextColumn();
		UI::Text(key);
		UI::TableNextColumn();
		UI::Text(value);
	}
}
