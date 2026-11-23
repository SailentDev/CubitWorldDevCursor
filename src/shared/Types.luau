--!strict
export type PetRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythical"
export type PetElement = "Water" | "Fire" | "Earth" | "Wind" | "Light" | "Dark"
export type CurrencyType = "Coins"
export type SettingKey = "FOV" | "MusicVol" | "ShowFPS" | "GlobalShadows"

export type PetInfo = {
	Name: string,
	Rarity: PetRarity,
	BaseDamage: number,
	BaseHp: number,
	Element: PetElement,
	IconId: string,
	IconOffset: Vector2,
	IconSize: Vector2,
}

export type EggInfo = {
	Name: string,
	Price: number,
	CurrencyType: CurrencyType,
	LayoutOrder: number,
	DropChances: { [string]: number },
}

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

export type PetInstanceData = {
	petName: string,
	level: number,
}

export type EquippedPetInfo = {
	uuid: string,
	petName: string,
}

export type ProfileData = {
	DataVersion: number,
	Coins: number,
	Pets: { [string]: PetInstanceData },
	Eggs: { [string]: number },
	EquippedPets: { string },
	Settings: Settings,
}

export type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

export type VoidSignal = {
	Connect: (self: VoidSignal, listener: () -> ()) -> SignalConnection,
}

export type LastSaveSignal = {
	Connect: (self: LastSaveSignal, listener: (reason: "Manual" | "External" | "Shutdown") -> ()) -> SignalConnection,
}

export type PlayerProfile = {
	Data: ProfileData,
	FirstSessionTime: number,
	SessionLoadCount: number,
	Key: string,
	OnSave: VoidSignal,
	OnLastSave: LastSaveSignal,
	OnSessionEnd: VoidSignal,
	IsActive: (self: PlayerProfile) -> boolean,
	Reconcile: (self: PlayerProfile) -> (),
	EndSession: (self: PlayerProfile) -> (),
	AddUserId: (self: PlayerProfile, userId: number) -> (),
	RemoveUserId: (self: PlayerProfile, userId: number) -> (),
	Save: (self: PlayerProfile) -> (),
}

return nil