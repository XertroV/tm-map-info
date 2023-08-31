namespace MapInfo {
    shared class Data {
        string uid;
        string author;
        // Converted to openplanet color string
        string Name;
        string RawName;
        // Without format codes
        string CleanName;

        string AuthorAccountId = "";
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
        string DateStr = "";

        // -1 for loading, 0 for no, 1 for yes
        int UploadedToNadeo = -1;

        // -1 for loading, 0 for no, 1 for yes
        int UploadedToTMX = -1;
        int TMXAuthorID = -1;
        int TrackID = -1;
        string TrackIDStr = "...";
        // When `null`, there's no TMX info. It should never be Json::Type::Null.
        Json::Value@ TMX_Info = null;

        uint NbPlayers = LoadingNbPlayersFlag;
        uint WorstTime = 0;
        string NbPlayersStr = "...";
        string WorstTimeStr = "...";
        string AuthorTimeStr = "...";

        string TOTDDate = "";
        int TOTDDaysAgo = -1;
        string TOTDStr = "...";

        uint LoadingStartedAt = Time::Now;
        bool LoadedMapData = false;
        bool LoadedNbPlayers = false;
        bool LoadedWasTOTD = false;

        int UploadedToTmDojo = -1;
        Json::Value@ TmDojoData = null;

        bool get_DoneLoading() {
            return LoadedMapData && LoadedNbPlayers && LoadedWasTOTD;
        }
    }
}
