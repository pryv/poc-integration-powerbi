//Written by Chris Webb - Crossjoin Consulting Limited
//Email: chris@crossjoin.co.uk

//NB This is a prototype and has not been fully tested

//To Do
//1) Refactor code
//2) Should username/password authentication be used, so that credentials can be stored in Power BI's secure credential store?
//3) Test all combinations of parameters for Pryv.Events()
//4) Add/change features based on user feedback and testing



// This file contains your Data Connector logic
section Pryv;

[DataSource.Kind="Pryv", Publish="Pryv.Publish"]
shared Pryv.Contents = (
                        URL as text,
                        optional fromTime as datetime,
                        optional toTime as datetime,
                        optional limit as number
                        ) as table =>
let
    getStreams = Pryv.Streams(URL),
    GetRecords = Table.ToRecords(getStreams),
    GetStreams = List.Generate(
                    ()=>[CurrentList = GetRecords, CurrentPosition=0],
                    each [CurrentPosition]<List.Count([CurrentList]),
                    each [
                        CurrentList = 
                            if List.Count([CurrentList]{[CurrentPosition]}[children])=0 
                            then [CurrentList] 
                            else List.InsertRange([CurrentList], [CurrentPosition]+1,[CurrentList]{[CurrentPosition]}[children]), 
                        CurrentPosition=[CurrentPosition]+1], 
                    each [CurrentList]{[CurrentPosition]}
                    ),

    #"Converted to Table" = Table.FromList(GetStreams, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = 
        try 
            Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"}, {"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"})
        otherwise
            #table({"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"},{}),         
    #"Removed Other Columns" = Table.SelectColumns(#"Expanded Column1",{"name", "parentId", "id"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Removed Other Columns",{{"name", type text}, {"parentId", type text}, {"id", type text}}),
    #"Added Custom" = Table.AddColumn(#"Changed Type", "Events", each Pryv.Events(URL,fromTime, toTime, {[id]}, null, null, null,null, null,limit,null,null,null), EventsType)
    
in
    #"Added Custom";

[DataSource.Kind="Pryv"]
shared Pryv.Events = (
                        URL as text,
                        optional fromTime as datetime,
                        optional toTime as datetime,
                        optional streams as list,
                        optional tags as list,
                        optional types as list,
                        optional running as logical,
                        optional sortAscending as logical,
                        optional skip as number,
                        optional limit as number,
                        optional state as text,
                        optional modifiedSince as number,
                        optional includeDeletions as logical
                        ) as table =>
let
    getUsernameAuth = ShredInputURL(URL),
    getUsernameDomain = getUsernameAuth[UsernameDomain],
    getAuth = getUsernameAuth[Auth],
    baseURL = "https://" & getUsernameDomain,

    //Build query string using the RelativePath option - can't use the Query option because some parameters like streams may be duplicated
    queryOptions = "auth=" & getAuth,
    addfromTime = if fromTime=null then queryOptions else queryOptions & "&fromTime=" & Text.From(DateTimeToTimestamp(fromTime)),
    addtoTime = if toTime=null then addfromTime else addfromTime & "&toTime=" & Text.From(DateTimeToTimestamp(toTime)),
    addstreams = if streams=null then addtoTime else addtoTime & Text.Combine(List.Transform(streams, each "&streams[]=" & _),""),
    addtags = if tags=null then addstreams else addstreams & Text.Combine(List.Transform(tags, each "&tags[]=" & _),""),
    addtypes = if types=null then addtags else addtags & Text.Combine(List.Transform(types, each "&types[]=" & _),""),
    addrunning = if running=null then addtypes else addtypes & "&running=" & Text.From(running),
    addsortAscending = if sortAscending=null then addrunning else addrunning & "&sortAscending=" & Text.From(sortAscending),
    addskip = if skip=null then addsortAscending else addsortAscending & "&skip=" & Text.From(skip),
    addlimit = if limit=null then addskip else addskip & "&limit=" & Text.From(limit),
    addstate = if state=null then addlimit else addlimit & "&state=" & state,
    addmodifiedSince = if modifiedSince=null then addstate else "&modifiedSince=" & Text.From(modifiedSince),
    addincludeDeletions = if includeDeletions=null then addmodifiedSince else addmodifiedSince & "&includeDeletions=" & Text.From(includeDeletions),

    //call web service and get the results
    callWebService = Web.Contents(baseURL, [RelativePath="events?" & addincludeDeletions]),
    Source = Json.Document(callWebService),
    events = Source[events],

    //flatten the results down to a table where each row is an event
    #"Converted to Table" = Table.FromList(events, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" =
        try 
            Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"content", "streamId", "type", "time", "tags", "created", "createdBy", "modified", "modifiedBy", "id", "duration", "references", "description", "attachments", "clientData", "trashed"}, {"content", "streamId", "type", "time", "tags", "created", "createdBy", "modified", "modifiedBy", "id", "duration", "references", "description", "attachments", "clientData", "trashed"})
        otherwise
            #table({"content", "streamId", "type", "time", "tags", "created", "createdBy", "modified", "modifiedBy", "id", "duration", "references", "description", "attachments", "clientData", "trashed"},{}),
    #"Added Custom" = Table.AddColumn(#"Expanded Column1", "datetime", each TimestampToDateTime([time])),
    #"Changed Type" = Table.TransformColumnTypes(#"Added Custom",{{"datetime", type datetime}}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Changed Type",{{"type", type text}, {"time", Int64.Type}, {"created", Int64.Type}, {"createdBy", type text}, {"modified", Int64.Type}, {"modifiedBy", type text}, {"id", type text}, {"streamId", type text}, {"content", type number}}),
    //any rows where the content column contains an error after being cast to a number are non-numeric and can be ignored
    #"Removed Errors" = Table.RemoveRowsWithErrors(#"Changed Type1", {"content"})
in
    #"Removed Errors";

 [DataSource.Kind="Pryv"]
 shared Pryv.Streams = (URL as text) as table =>
 let
    getUsernameAuth = ShredInputURL(URL),
    getUsernameDomain = getUsernameAuth[UsernameDomain],
    getAuth = getUsernameAuth[Auth],
    baseURL = "https://" & getUsernameDomain,
    callWebService = Web.Contents(baseURL, [RelativePath="streams?auth=" & getAuth]),
    Source = Json.Document(callWebService),
    streams = Source[streams],
    #"Converted to Table" = Table.FromList(streams, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Expanded Column1" = 
        try
            Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"}, {"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"})
        otherwise
            #table({"name", "parentId", "created", "createdBy", "modified", "modifiedBy", "clientData", "id", "children", "singleActivity", "trashed"},{}),
    #"Changed Type" = Table.TransformColumnTypes(#"Expanded Column1",{{"name", type text}, {"parentId", type text}, {"created",  Int64.Type}, {"createdBy", type text}, {"modified", Int64.Type}, {"modifiedBy", type text}, {"id", type text}, {"trashed", type logical}, {"singleActivity", type logical}})
in
    #"Changed Type";

// Helper functions and type definitions

//Defines a table type for Events
EventsType = type table [
                    content = number, 
                    streamId = text, 
                    type = text, 
                    time = number, 
                    tags = any, 
                    created = number,
                    createdBy = text, 
                    modified = number, 
                    modifiedBy = text, 
                    id = text, 
                    duration = number, 
                    references = any, 
                    description = text, 
                    attachments = any, 
                    clientData = any, 
                    trashed = logical,
                    datetime = datetime
                    ];

//Extract username and password from input URL
ShredInputURL = (SourceURL as text) as record =>
let
    UsernameDomain = Text.BetweenDelimiters(SourceURL , "/", "/", 1, 0),
    Auth = Text.AfterDelimiter(SourceURL, "/", 4),
    Output = [UsernameDomain=UsernameDomain, Auth=Auth]
in
    Output;

//Convert a timestamp in Unix time format to a date/time value
TimestampToDateTime = (inputTimestamp as number) as datetime =>
    try
        #datetime(1970,1,1,0,0,0) + #duration(0,0,0,inputTimestamp)
    otherwise
        #datetime(1970,1,1,0,0,0);

DateTimeToTimestamp = (inputDateTime as datetime) as number =>
    try
        Duration.TotalSeconds(inputDateTime - #datetime(1970,1,1,0,0,0))
    otherwise
        0;

//Add metadata to a table to make it a navigation table
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;


// Data Source Kind description
Pryv = [
    Authentication = [
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
Pryv.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Pryv.Icons,
    SourceTypeImage = Pryv.Icons
];

Pryv.Icons = [
    Icon16 = { Extension.Contents("Pryv16.png"), Extension.Contents("Pryv20.png"), Extension.Contents("Pryv24.png"), Extension.Contents("Pryv32.png") },
    Icon32 = { Extension.Contents("Pryv32.png"), Extension.Contents("Pryv40.png"), Extension.Contents("Pryv48.png"), Extension.Contents("Pryv64.png") }
];
