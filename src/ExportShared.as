namespace MapInfo {
    shared class Data {
        string uid;
        string author;
        // Converted to openplanet color string
        string Name;
        string RawName;
        // Without format codes
        string CleanName;
        string MapComment;
        bool HasMapComment;

        string AuthorAccountId = "";
        string AuthorCurrentName = "";
        string AuthorDisplayName = "";
        string AuthorWebServicesUserId = "";
        string AuthorCountryFlag = "";
        string FileName = "";
        string FileUrl = "";
        string ThumbnailUrl = "";
        uint TimeStamp = 0;
        uint AuthorScore = 0;
        uint GoldScore = 0;
        uint SilverScore = 0;
        uint BronzeScore = 0;
        uint ChampionScore = 0;
        string ChampionTimeStr = "...";
        string AuthorTimeStr = "...";
        string GoldTimeStr = "...";
        string SilverTimeStr = "...";
        string BronzeTimeStr = "...";
        // if a Champion Medal exists (and that plugin is installed) it'll be inserted at index=0
        uint[] OrderedMedalTimesUint = {-1, -1, -1, -1};
        string[] OrderedMedalTimes = {"...", "...", "...", "..."};
        vec4[] OrderedMedalColors = {
            vec4(0.000f, 0.471f, 0.035f, 1.0), // Author
            vec4(0.871f, 0.737f, 0.259f, 1.0), // Gold
            vec4(0.537f, 0.604f, 0.604f, 1.0), // Silver
            vec4(0.604f, 0.400f, 0.259f, 1.0), // Bronze
        };
        string DateStr = "";

        // -1 for loading, 0 for no, 1 for yes
        int UploadedToNadeo = -1;

        // -1 for loading, 0 for no, 1 for yes
        int UploadedToTMX = -1;
        int TMXAuthorID = -1;
        int TrackID = -1;
        string TrackIDStr = "...";
        // -1 for unset
        int TMXAwards = -1;
        string TMXAwardsStr = "...";
        string TMXMapTags;
        // When `null`, there's no TMX info. It should never be Json::Type::Null.
        Json::Value@ TMX_Info = null;

        uint NbPlayers = LoadingNbPlayersFlag;
        uint WorstTime = 0;
        string NbPlayersStr = "...";
        string WorstTimeStr = "...";

        string TOTDDate = "";
        int TOTDDaysAgo = -1;
        string TOTDStr = "...";

        uint LoadingStartedAt = Time::Now;
        bool LoadedMapData = false;
        bool LoadedNbPlayers = false;
        bool LoadedWasTOTD = false;

        int UploadedToTmDojo = -1;
        Json::Value@ TmDojoData = null;

        int PersonalBestTime = -1;
        int PersonalBestMedal = -1;

        bool get_DoneLoading() {
            return LoadedMapData && LoadedNbPlayers && LoadedWasTOTD;
        }
    }
}
