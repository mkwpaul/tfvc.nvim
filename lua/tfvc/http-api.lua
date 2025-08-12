-- Microsoft provides swagger API definitions for the tfvc 'rest' API
-- https://github.com/MicrosoftDocs/vsts-rest-api-specs/tree/master/specification/tfvc
--
-- TODO: create a swagger code generator that generates lua code making http-requests with plenary.curl
-- and that generates luadoc annotations for functions and type defintions for request-parameters and response-data
--
-- the existing swagger code generator for lua uses other libraries to make http requests and serialize and parse json
-- which I don't want to depend on when nvim has json parsing built in and I depend on plenary anyway.
--
-- manually writing a client would be lots of wasted effort if I wanted to support different API versions (or other http json API's)
--

---@class AssociatedWorkItem
---@field assignedTo string?
---@field id number? Id of associated the work item.
---@field state string?
---@field title string?
---@field url string? REST Url of the work item.
---@field webUrl string?
---@field workItemType string?

---@class Change
---@field changeType any? The type of change that was made to the item.
---@field item string? Current version.
---@field newContent any? Content of the item after the change.
---@field sourceServerItem string? Path of the item on the server.
---@field url string? URL to retrieve the item.

---@class CheckinNote
---@field name string?
---@field value string?

---@class FileContentMetadata
---@field contentType string?
---@field encoding number?
---@field extension string?
---@field fileName string?
---@field isBinary boolean?
---@field isImage boolean?
---@field vsLink string?

---@class GitRepository
---@field _links any?
---@field defaultBranch string?
---@field id string?
---@field isFork boolean? True if the repository was created as a fork
---@field name string?
---@field parentRepository any?
---@field project any?
---@field remoteUrl string?
---@field sshUrl string?
---@field url string?
---@field validRemoteUrls table?

---@class GitRepositoryRef
---@field collection any? Team Project Collection where this Fork resides
---@field id string?
---@field isFork boolean? True if the repository was created as a fork
---@field name string?
---@field project any?
---@field remoteUrl string?
---@field sshUrl string?
---@field url string?

---@class GraphSubjectBase
---@field _links any? This field contains zero or more interesting links about the graph subject. These links may be invoked to obtain additional relationships or more detailed information about this graph subject.
---@field descriptor string? The descriptor is the primary way to reference the graph subject while the system is running. This field will uniquely identify the same graph subject across both Accounts and Organizations.
---@field displayName string? This is the non-unique display name of the graph subject. To change this field, you must alter its value in the source provider.
---@field url string? This url is the full route to the source resource of this graph subject.

---@class IdentityRef
---@field directoryAlias string?
---@field id string?
---@field imageUrl string?
---@field inactive boolean?
---@field isAadIdentity boolean?
---@field isContainer boolean?
---@field profileUrl string?
---@field uniqueName string?

---@class ItemContent
---@field content string?
---@field contentType any?

---@class ItemModel
---@field _links any?
---@field content string?
---@field contentMetadata any?
---@field isFolder boolean?
---@field isSymLink boolean?
---@field path string?
---@field url string?

---@class ReferenceLinks The class to represent a collection of REST reference links.
---@field links any? The readonly view of the links. Because Reference links are readonly, we only want to expose them as read only.

---@class TeamProjectCollectionReference Reference object for a TeamProjectCollection.
---@field id string? Collection Id.
---@field name string? Collection Name.
---@field url string? Collection REST Url.

---@class TeamProjectReference Represents a shallow reference to a TeamProject.
---@field abbreviation string? Project abbreviation.
---@field description string? The project's description (if any).
---@field id string? Project identifier.
---@field name string? Project name.
---@field revision number? Project revision.
---@field state any? Project state.
---@field url string? Url to the full version of the object.
---@field visibility any? Project visibility.

---@class TfvcBranch Class representing a branch object.
---@field children table? List of children for the branch.
---@field mappings table? List of branch mappings.
---@field parent any? Path of the branch's parent.
---@field relatedBranches table? List of paths of the related branches.

---@class TfvcBranchMapping A branch mapping.
---@field depth string? Depth of the branch.
---@field serverItem string? Server item for the branch.
---@field type string? Type of the branch.

---@class TfvcBranchRef Metadata for a branchref.
---@field _links any? A collection of REST reference links.
---@field createdDate string? Creation date of the branch.
---@field description string? Branch description.
---@field isDeleted boolean? Is the branch deleted?
---@field owner any? Alias or display name of user
---@field url string? URL to retrieve the item.

---@class TfvcChange A change.
---@field mergeSources table? List of merge sources in case of rename or branch creation.
---@field pendingVersion number? Version at which a (shelved) change was pended against

---@class TfvcChangeset A collection of changes.
---@field accountId string? Changeset Account Id also known as Organization Id.
---@field changes table? List of associated changes.
---@field checkinNotes table? List of Checkin Notes for the changeset.
---@field collectionId string? Changeset collection Id.
---@field hasMoreChanges boolean? True if more changes are available.
---@field policyOverride any? Policy Override for the changeset.
---@field teamProjectIds table? Team Project Ids for the changeset.
---@field workItems table? List of work items associated with the changeset.

---@class TfvcChangesetRef Metadata for a changeset.
---@field _links any? A collection of REST reference links.
---@field author any? Alias or display name of user.
---@field changesetId number? Changeset Id.
---@field checkedInBy any? Alias or display name of user.
---@field comment string? Comment for the changeset.
---@field commentTruncated boolean? Was the Comment result truncated?
---@field createdDate string? Creation date of the changeset.
---@field url string? URL to retrieve the item.

---@class TfvcChangesetSearchCriteria Criteria used in a search for change lists.
---@field author string? Alias or display name of user who made the changes.
---@field followRenames boolean? Whether or not to follow renames for the given item being queried.
---@field fromDate string? If provided, only include changesets created after this date (string).
---@field fromId number? If provided, only include changesets after this changesetID.
---@field includeLinks boolean? Whether to include the _links field on the shallow references.
---@field itemPath string? Path of item to search under.
---@field toDate string? If provided, only include changesets created before this date (string).
---@field toId number? If provided, a version descriptor for the latest change list to include.

---@class TfvcChangesetsRequestData Request body for Get batched changesets.
---@field changesetIds table? List of changeset Ids.
---@field commentLength number? Max length of the comment.
---@field includeLinks boolean? Whether to include the _links field on the shallow references

---@class TfvcItem Metadata for an item.
---@field changeDate string? Item changed datetime.
---@field deletionId number? Greater than 0 if item is deleted.
---@field hashValue string? MD5 hash as a base 64 string, applies to files only.
---@field isBranch boolean? True if item is a branch.
---@field isPendingChange boolean? True if there is a change pending.
---@field size number? The size of the file, if applicable.
---@field version number? Changeset version Id.

---@class TfvcItemDescriptor Item path and Version descriptor properties
---@field path string? Item path.
---@field recursionLevel any? Defaults to OneLevel.
---@field version string? Specify the desired version, can be null or empty string only if VersionType is latest or tip.
---@field versionOption any? Defaults to None.
---@field versionType any? Defaults to Latest.

---@class TfvcItemRequestData Request body used by Get Items Batch
---@field includeContentMetadata boolean? If true, include metadata about the file type
---@field includeLinks boolean? Whether to include the _links field on the shallow references
---@field itemDescriptors table?

---@class TfvcLabel Metadata for a label.
---@field items table? List of items.

---@class TfvcLabelRef Metadata for a Label.
---@field _links any? Collection of reference links.
---@field description string? Label description.
---@field id number? Label Id.
---@field labelScope string? Label scope.
---@field modifiedDate string? Last modified datetime for the label.
---@field name string? Label name.
---@field owner any? Label owner.
---@field url string? Label Url.

---@class TfvcLabelRequestData
---@field includeLinks boolean? Whether to include the _links field on the shallow references
---@field itemLabelFilter string?
---@field labelScope string?
---@field maxItemCount number?
---@field name string?
---@field owner string?

---@class TfvcMergeSource
---@field isRename boolean? Indicates if this a rename source. If false, it is a merge source.
---@field serverItem string? The server item of the merge source.
---@field versionFrom number? Start of the version range.
---@field versionTo number? End of the version range.

---@class TfvcPolicyFailureInfo Policy failure information.
---@field message string? Policy failure message.
---@field policyName string? Name of the policy that failed.

---@class TfvcPolicyOverrideInfo Information on the policy override.
---@field comment string? Overidden policy comment.
---@field policyFailures table? Information on the failed policy that was overridden.

---@class TfvcShallowBranchRef This is the shallow branchref class.
---@field path string? Path for the branch.

---@class TfvcShelveset Metadata for a shelveset.
---@field changes table? List of changes.
---@field notes table? List of checkin notes.
---@field policyOverride any? Policy override information if applicable.
---@field workItems table? List of associated workitems.

---@class TfvcShelvesetRef Metadata for a shallow shelveset.
---@field _links any? List of reference links for the shelveset.
---@field comment string? Shelveset comment.
---@field commentTruncated boolean? Shelveset comment truncated as applicable.
---@field createdDate string? Shelveset create date.
---@field id string? Shelveset Id.
---@field name string? Shelveset name.
---@field owner any? Shelveset Owner.
---@field url string? Shelveset Url.

---@class TfvcShelvesetRequestData
---@field includeDetails boolean? Whether to include policyOverride and notes Only applies when requesting a single deep shelveset
---@field includeLinks boolean? Whether to include the _links field on the shallow references. Does not apply when requesting a single deep shelveset object. Links will always be included in the deep shelveset.
---@field includeWorkItems boolean? Whether to include workItems
---@field maxChangeCount number? Max number of changes to include
---@field maxCommentLength number? Max length of comment
---@field name string? Shelveset name
---@field owner string? Owner's ID. Could be a name or a guid.

---@class TfvcVersionDescriptor Version descriptor properties.
---@field version string? Version object.
---@field versionOption any?
---@field versionType any?

---@class VersionControlProjectInfo
---@field defaultSourceControlType any?
---@field project any?
---@field supportsGit boolean?
---@field supportsTFVC boolean?

---@class VssJsonCollectionWrapper This class is used to serialized collections as a single JSON object on the wire, to avoid serializing JSON arrays directly to the client, which can be a security hole
---@field value string?

---@class VssJsonCollectionWrapperBase
---@field count number?

local function _apis_tfvc_changesets_changes()
end

local M = {}
---@field VersionControlProjectInfo
M['/{organization}/_apis/tfvc/changesets/{id}/changes'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/_apis/tfvc/changesets/{id}/workItems'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/_apis/tfvc/changesetsbatch'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.post({})
end
M['/{organization}/_apis/tfvc/labels/{labelId}/items'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/_apis/tfvc/shelvesets'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/_apis/tfvc/shelvesets/changes'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/_apis/tfvc/shelvesets/workitems'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/branches'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/changesets'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.post({})
end
M['/{organization}/{project}/_apis/tfvc/changesets'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/changesets/{id}'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/itembatch'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.post({})
end
M['/{organization}/{project}/_apis/tfvc/items'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/labels'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
M['/{organization}/{project}/_apis/tfvc/labels/{labelId}'] = function(opts)
  local curl = require ('plenary.curl') 
  return curl.get({})
end
return M
