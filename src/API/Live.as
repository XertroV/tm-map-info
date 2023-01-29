namespace Live {
    /* example ret val:
            RetVal = {"monthList": MonthObj[], "itemCount": 23, "nextRequestTimestamp": 1654020000, "relativeNextRequest": 22548}
            MonthObj = {"year": 2022, "month": 5, "lastDay": 31, "days": DayObj[], "media": {...}}
            DayObj = {"campaignId": 3132, "mapUid": "fJlplQyZV3hcuD7T1gPPTXX7esd", "day": 4, "monthDay": 31, "seasonUid": "aad0f073-c9e0-45da-8a70-c06cf99b3023", "leaderboardGroup": null, "startTimestamp": 1596210000, "endTimestamp": 1596300000, "relativeStart": -57779100, "relativeEnd": -57692700}
        as of 2022-05-31 there are 23 items, so limit=100 will give you all data till 2029.
    */
    Json::Value@ GetTotdByMonth(uint length = 100, uint offset = 0) {
        return CallLiveApiPath("/api/token/campaign/month?" + LengthAndOffset(length, offset));
    }
}
