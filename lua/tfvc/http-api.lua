--[[
Parameter 	Type 	Default 	Notes
URL 			
instance 	string 		TFS server name ({server:port}).
Query 			
api-version 	string 		Version of the API to use.
searchCriteria.itemPath 	string 	$/ 	Changesets for the item at this path.
searchCriteria.version 	string 		Changesets at this version of the item.
searchCriteria.versionType 	string 	branch 	If the version is specified, the type of version that is used.
searchCriteria.versionOption 	string 		If the version is specified, an optional modifier for the version.
searchCriteria.author 	string 		Person who checked in the changeset.
Example: searchCriteria.author=johnsmith@live.com.
searchCriteria.fromId 	int 		ID of the oldest changeset to return.
searchCriteria.toId 	int 		ID of the newest changeset to return.
searchCriteria.fromDate 	DateTime 		Date and time of the earliest changeset to return.
searchCriteria.toDate 	DateTime 		Date and time of the latest changesets to return.
$top 	int 	100 	The maximum number of results to return.
$skip 	int 	0 	Number of results to skip.
$orderby 	"id asc" or "id desc" 	id desc 	Results are sorted by ID in descending order by default. Use id asc to sort by ID in ascending order.
maxCommentLength 	int 	full comment 	Return up to this many characters of the comment
  --]]

--- @class tfvc_changesets_request
--- @field instance string TFS server name ({server:port}).
--- @field api_version string Version of the API to use.
--- @field top integer The maximum number of results to return. Default: 100
--- @field skip integer Number of results to skip. Default: 0
--- @field orderby string Results are sorted by ID in descending order by default. Use "id asc" to sort by ID in ascending order. Default: "id desc"
--- @field maxCommentLength integer Return up to this many characters of the comment. Default: full comment
--- @field searchCriteria searchCriteria

--- @alias os.date string
--- @class searchCriteria table Table of search criteria:
---   @field itemPath string Changesets for the item at this path. Default: $/
---   @field version string Changesets at this version of the item.
---   @field versionType string If the version is specified, the type of version that is used. Default: branch
---   @field versionOption string If the version is specified, an optional modifier for the version.
---   @field author string Person who checked in the changeset.
---   @field fromId integer ID of the oldest changeset to return.
---   @field toId integer ID of the newest changeset to return.
---   @field fromDate string|os.date Date and time of the earliest changeset to return.
---   @field toDate string|os.date Date and time of the latest changesets to return.
