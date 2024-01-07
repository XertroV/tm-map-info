[Setting hidden]
bool S_ShowMapInfo = true;

enum ShowTimeSetting {
    Author_Time,
    Worst_Time
}
[Setting category="General" name="Show worst time or author time"]
ShowTimeSetting S_ShowWhichTime = ShowTimeSetting::Worst_Time;

enum AboveRecChoice {
    None = 0,
    Only_Map_Name = 1,
    Only_Author = 2,
    Both = 3,
}
[Setting category="General" name="Show Map Name and/or Author above records"]
AboveRecChoice S_DrawTitleAuthorAboveRecords = AboveRecChoice::Both;

[Setting category="General" name="Show TMX Track ID below records if it exists"]
bool S_DrawTMXBelowRecords = true;

[Setting category="General" name="Lakanta Mode" description="Middle-clicking the TMX Track ID below the records panel will load the next map (by TMX TrackID). Additionally, the TMX ID of that track will be copied to the clipboard."]
bool S_LakantaMode = false;

[Setting category="General" name="Next TMX Map Hotkey" description="When Lakanta mode is active, this hotkey will take you to the next map. Default: `]` (Oem6)"]
VirtualKey S_LakantaModeHotKey = VirtualKey::Oem6;

[Setting category="General" name="Show Debug Window (must be in a map)"]
bool S_ShowDebugUI = false;

[Setting category="General" name="Add Debug Window toggle to Plugins Menu"]
bool S_ShowDebugMenuItem = false;

[Setting category="General" name="Log Level"]
LogLevel S_LogLevel = LogLevel::Info;


[Setting category="Medal Times" name="Show medal times below records"]
bool S_DrawMedalsBelowRecords = true;

[Setting category="Medal Times" name="Show only best 2 medal times below records"]
bool S_DrawOnly2MedalsBelowRecords = false;

[Setting category="Medal Times" name="Show PB delta to medals"]
bool S_ShowPbDeltaToMedals = true;

[Setting category="Medal Times" name="Hide Medals after the first worse than PB"]
bool S_HideMedalsWorseThanPb = true;

[Setting category="Medal Times" name="Negative PB Delta Color" color]
vec4 S_DeltaColorNegative = vec4(0.170f, 0.463f, 0.943f, 1.000f);

[Setting category="Medal Times" name="Positive PB Delta Color" color]
vec4 S_DeltaColorPositive = vec4(0.930f, 0.308f, 0.053f, 1.000f);




[Setting category="Loading Screen" name="Show map info on loading screen"]
bool S_ShowLoadingScreenInfo = true;

[Setting category="Loading Screen" name="Loading Screen Y Offset (%)" min=0 max=90]
float S_LoadingScreenYOffsetPct = 12.0;


[Setting category="Side Panel" name="Show author flags"]
bool S_ShowAuthorFlags = true;


#if DEPENDENCY_MANIAEXCHANGE
[Setting category="Integrations" name="Open TMX Links in the ManiaExchange plugin?"]
bool S_OpenTmxInManiaExchange = true;
#else
bool S_OpenTmxInManiaExchange = false;
#endif

[Setting category="Persistent Window" name="Show Persistent Window" description="Note: this is currently kinda rough, but will get a cleanup pass in the near future"]
bool S_ShowPersistentUI = false;

[Setting category="Persistent Window" name="Show map publish date"]
bool SP_ShowPubDate = true;

[Setting category="Persistent Window" name="Show TotD date"]
bool SP_ShowTotDDate = true;

[Setting category="Persistent Window" name="Show number of players"]
bool SP_ShowNbPlayers = true;

[Setting category="Persistent Window" name="Show worst time"]
bool SP_ShowWorstTime = true;

[Setting category="Persistent Window" name="Show TMX/Dojo ID"]
bool SP_ShowTMXDojo = true;
