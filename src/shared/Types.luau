--!strict
export type Settings = {
	FOV: number,
	MusicVol: number,
	ShowFPS: boolean,
	GlobalShadows: boolean,
}

export type SettingsUpdate = {
	FOV: number?,
	MusicVol: number?,
	ShowFPS: boolean?,
	GlobalShadows: boolean?,
}

export type ProfileData = {
	Coins: number,
	Pets: { string },
	Settings: Settings,
}

export type Profile = {
	Data: ProfileData,
	MetaData: {
		ProfileCreateTime: number,
		SessionStartTime: number,
		ActiveSession: { number }?,
		ForceLoadSession: { number }?,
		MetaTags: { [string]: any },
	},
	KeyName: string,
	IsActive: (self: Profile) -> boolean,
	EndSession: (self: Profile) -> (),
	Released: (() -> ())?,
	OnSessionEnd: any?, -- Supports connection-based termination signals
}

return nil