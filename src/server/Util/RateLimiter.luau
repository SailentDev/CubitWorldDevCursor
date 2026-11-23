--!strict
type Bucket = {
	tokens: number,
	lastRefill: number,
}

export type RateLimiter = {
	_capacity: number,
	_refillPerSec: number,
	_buckets: { [Player]: Bucket },
	Consume: (self: RateLimiter, player: Player) -> boolean,
	Clear: (self: RateLimiter, player: Player) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSec: number): RateLimiter
	assert(typeof(capacity) == "number" and capacity > 0, "RateLimiter capacity must be > 0")
	assert(typeof(refillPerSec) == "number" and refillPerSec >= 0, "RateLimiter refillPerSec must be >= 0")

	local self = {
		_capacity = capacity,
		_refillPerSec = refillPerSec,
		_buckets = {} :: { [Player]: Bucket },
	}
	return (setmetatable(self, RateLimiter) :: unknown) :: RateLimiter
end

function RateLimiter:Consume(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		self._buckets[player] = nil
		return false
	end

	local now = os.clock()
	local bucket = self._buckets[player]

	if not bucket then
		if self._capacity < 1 then
			return false
		end
		self._buckets[player] = {
			tokens = self._capacity - 1,
			lastRefill = now,
		}
		return true
	end

	local elapsed = math.max(0, now - bucket.lastRefill)
	local tokens = math.min(self._capacity, bucket.tokens + (elapsed * self._refillPerSec))
	bucket.lastRefill = now

	if tokens < 1 then
		bucket.tokens = tokens
		return false
	end

	bucket.tokens = tokens - 1
	return true
end

function RateLimiter:Clear(player: Player): ()
	self._buckets[player] = nil
end

return RateLimiter