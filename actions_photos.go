/*
 * Copyright (c) Cherri
 */

package main

// Photos (com.apple.mobileslideshow) actions added in iOS 27, read from device exports of every action. Shortcuts
// only writes a parameter that was touched, so only parameters seen in an export are defined.
const photosBundleIdentifier = "com.apple.mobileslideshow"

// photosIntent builds the app intent descriptor shared by the Photos actions, varying only by identifier.
func photosIntent(appIntentIdentifier string) appIntent {
	return appIntent{
		name:                "Photos",
		bundleIdentifier:    photosBundleIdentifier,
		appIntentIdentifier: appIntentIdentifier,
	}
}

// photosAction defines a Photos intent action, keeping the identifier and descriptor from drifting apart.
func photosAction(title, description, intentIdentifier string, parameters []parameterDefinition) *actionDefinition {
	return &actionDefinition{
		doc: selfDoc{
			title:       title,
			description: description,
			category:    "photos",
		},
		appIdentifier: photosBundleIdentifier,
		identifier:    intentIdentifier,
		appIntent:     photosIntent(intentIdentifier),
		minVersion:    27,
		parameters:    parameters,
	}
}

func init() {
	enumerations["photosLibraryViews"] = []string{"both", "personal", "shared"}

	actions["enhancePhotos"] = photosAction(
		"Enhance Photos",
		"Automatically enhances `photos`.",
		"EnhanceIntent",
		[]parameterDefinition{
			{name: "photos", validType: Variable, key: "assets", optional: true},
		},
	)

	// iOS 27 replaced the Rename Album action, and the old identifier now shows as an unknown action.
	actions["renameAlbum"] = photosAction(
		"Rename Album",
		"Renames `album` to `newTitle`.",
		"RenameAlbumIntent",
		[]parameterDefinition{
			{name: "album", validType: Variable, key: "album", optional: true},
			{name: "newTitle", validType: String, key: "title", optional: true},
		},
	)

	actions["favoritePhotos"] = photosAction(
		"Favorite Photos",
		"Favorites `photos`.",
		"FavoriteAssetsIntent",
		[]parameterDefinition{
			{name: "photos", validType: Variable, key: "assets", optional: true},
		},
	)

	actions["hidePhotos"] = photosAction(
		"Hide Photos",
		"Hides `photos`.",
		"HideAssetsIntent",
		[]parameterDefinition{
			{name: "photos", validType: Variable, key: "assets", optional: true},
		},
	)

	actions["openPhoto"] = photosAction(
		"Open Photo",
		"Opens `photo` in Photos.",
		"OpenAssetIntent",
		[]parameterDefinition{
			{name: "photo", validType: Variable, key: "target", optional: true},
		},
	)

	actions["deleteAlbums"] = photosAction(
		"Delete Albums",
		"Deletes `albums`.",
		"DeleteAlbumsIntent",
		[]parameterDefinition{
			{name: "albums", validType: Variable, key: "entities", optional: true},
		},
	)

	actions["createMemory"] = photosAction(
		"Create Memory",
		"Opens Photos to create a Memory from `description`.",
		"OpenMemoryCreationViewIntent",
		[]parameterDefinition{
			{name: "description", validType: String, key: "query", optional: true},
		},
	)

	actions["filterPhotosLibrary"] = photosAction(
		"Filter Photos Library",
		"Sets which library Photos shows: both, personal or shared.",
		"FilterLibraryIntent",
		[]parameterDefinition{
			{name: "view", validType: String, key: "viewMode", enum: "photosLibraryViews", optional: true},
		},
	)

	// Albums are an entity query, so the sort and filter options that Shortcuts also writes are left to the Shortcut.
	var findAlbums = photosAction(
		"Find Albums",
		"Finds albums, optionally from the albums in `input`. Pick the sort and filter in the Shortcut.",
		"AlbumEntity",
		[]parameterDefinition{
			{name: "input", validType: Variable, key: "WFContentItemInputParameter", optional: true},
		},
	)
	findAlbums.appIntent.requiresAppInstallation = true
	findAlbums.outputType = Arr
	actions["findAlbums"] = findAlbums

	// Shared Albums is a share service, so it has no app intent descriptor.
	actions["addToSharedAlbum"] = &actionDefinition{
		doc: selfDoc{
			title:       "Add to Shared Album",
			description: "Adds `input` to a shared album. Pick the album in the Shortcut.",
			category:    "photos",
		},
		appIdentifier: photosBundleIdentifier,
		identifier:    "StreamShareService",
		minVersion:    27,
		parameters: []parameterDefinition{
			{name: "input", validType: Variable, key: "ImageInput", optional: true},
		},
	}
}
