--!strict
export type Settings = {
	FOV: number,
	MusicVol: number,
	ShowFPS: boolean,
	GlobalShadows: boolean,
	[string]: any, -- Restored to allow safe dynamic indexing in SettingsClient
}

export type SettingsUpdate = {
	FOV: number?,
	MusicVol: number?,
	ShowFPS: boolean?,
	GlobalShadows: boolean?,
	[string]: any, -- Restored
}

export type ProfileData = {
	Coins: number,
	Pets: { string },
	Settings: Settings,
	[string]: any, -- Restored to satisfy dictionary constraints
}

-- Client-safe representation of ProfileStore's Profile<T> structure
export type Profile = {
	Data: ProfileData,
	LastSavedData: ProfileData,
	FirstSessionTime: number,
	SessionLoadCount: number,
	Session: { PlaceId: number, JobId: string }?,
	RobloxMetaData: any,
	UserIds: { number },
	KeyInfo: DataStoreKeyInfo?,
	OnSave: any,
	OnLastSave: any,
	OnSessionEnd: any,
	OnAfterSave: any,
	ProfileStore: any,
	Key: string,

	IsActive: (self: Profile) -> boolean,
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, user_id: number) -> (),
	RemoveUserId: (self: Profile, user_id: number) -> (),
	MessageHandler: (self: Profile, fn: (message: any, processed: () -> ()) -> ()) -> (),
	Save: (self: Profile) -> (),
	SetAsync: (self: Profile) -> (),
}

export type ProfileDataStore = {
	[string]: any
}

return nil