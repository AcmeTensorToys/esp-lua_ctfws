-- logging for debugging
-- local dprint = function(...) end -- OFF
local dprint = function(...) print(...) end -- ON

-- common module initialization
cron.schedule("*/5 * * * *", function(e) OVL["nwfnet-sntp"]().dosntp(nil) end)
nwfnet = require "nwfnet"

-- Game logic modules
ctfws = OVL.ctfws()
ctfws:setFlags(0,0)

msg_tmr = tmr.create()
flg_tmr = tmr.create()
fla_tmr = tmr.create()
ctfws_lcd = OVL["ctfws-lcd"]()(ctfws, lcd, msg_tmr, flg_tmr, fla_tmr)
ctfws_tmr = tmr.create()

-- Draw the default display
ctfws_lcd:drawTimes()
ctfws_lcd:drawFlagsMessage("BOOT...")

-- MQTT plumbing
mqc, mqttUser = OVL.nwfmqtt().mkclient("nwfmqtt.conf")
if mqc == nil then
  print("CTFWS", "You forgot your MQTT configuration file")
end
local mqttLocnTopic  = string.format("ctfws/devc/%s/location",mqttUser)
local mqttBootTopic  = string.format("ctfws/dev/%s/beat",mqttUser)
mqc:lwt(mqttBootTopic,"dead",1,1)

-- This is not, properly speaking, OK, but it's so convenient
local boot_message_hack = 1
ctfws_lcd.attnState = 1 -- hackishly suppress attention() call
ctfws_lcd:drawMessage(string.format("I am: %s", mqttUser))
ctfws_lcd.attnState = nil

local myBSSID = "00:00:00:00:00:00"

local mqtt_reconn_cronentry
local function mqtt_reconn()
  dprint("CTFWS", "Trying reconn...")
  mqtt_reconn_cronentry = cron.schedule("* * * * *", function(e)
    mqc:close(); OVL.nwfmqtt().connect(mqc,"nwfmqtt.conf")
  end)
  OVL.nwfmqtt().connect(mqc,"nwfmqtt.conf")
end

local mqtt_beat_tmr = tmr.create()
mqtt_beat_tmr:register(20000, tmr.ALARM_AUTO, function(t)
    mqc:publish(mqttBootTopic,string.format("beat %d %s",rtctime.get(),myBSSID),1,1)
  end)

local function ctfws_lcd_draw_all()
    ctfws_lcd:reset()
    ctfws_lcd:drawFlags()
    ctfws_lcd:drawTimes()

    -- clear the message display if it hasn't been already after boot
    if boot_message_hack then
      ctfws_lcd:drawMessage("")
      boot_message_hack = nil
    end
end

local ctfws_start_tmr
local function ctfws_tmr_cb()
  -- draw the display, and if it tells us that the game is not in progress,
  -- wait a little longer before trying again, but don't unregister (like we
  -- used to).  This means we'll paint error messages periodically, but
  -- won't hammer the i2c bus with too many unnecessary updates.  It also
  -- means that a little NTP drift is OK.
  if not ctfws_lcd:drawTimes() then
    ctfws_tmr:alarm(3000,tmr.ALARM_AUTO,ctfws_start_tmr)
  end
end
function ctfws_start_tmr()
  ctfws_tmr:alarm(100,tmr.ALARM_AUTO,ctfws_tmr_cb)
end

nwfnet.onmqtt["init"] = function(c,t,m)
  dprint("MQTT", t, m)
  if t == "ctfws/game/config" then
    ctfws_tmr:unregister()
    if not m or m == "none"
     then ctfws:deconfig()
          ctfws_lcd_draw_all()
     else local st,     -- start time
	        sd,     -- setup duration
		nr,     -- number of rounds
		rd,     -- round duration
		nf,     -- number of flags
		gn,     -- game number
		tc      -- territory configuration string
	                --   st      sd      nr      rd      nf      gn      tc
	     = m:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+).*$")
          if st == nil
           then ctfws:deconfig()
           else -- the game's afoot!
                ctfws:config(tonumber(st), tonumber(sd), tonumber(nr),
                             tonumber(rd), tonumber(nf), tc)
                ctfws_start_tmr()
          end
          ctfws_lcd_draw_all()
    end
  elseif t == "ctfws/game/endtime" then
    ctfws:setEndTime(tonumber(m))
    ctfws_lcd_draw_all()
    ctfws_start_tmr() -- might have been unset; restart display if so
  elseif t == "ctfws/game/flags" then
   if not m or m == "" then
     if ctfws:setFlags("?","?") then ctfws_lcd:drawFlags() end
     return
   end
   local ts, fr, fy = m:match("^%s*(%d+)%s+(-?%d+)%s+(-?%d+).*$")
   if ts ~= nil then
     if ctfws:setFlags(tonumber(fr),tonumber(fy)) then ctfws_lcd:drawFlags() end
     return
   end
   -- we used to match on the ? explicitly, as in:
   --   if m:match("^%s*(%d+)%s+%?.*$") then ... end
   -- but for now, let's just take any ill-formed message
   if ctfws:setFlags("?","?") then ctfws_lcd:drawFlags() end
  elseif t == mqttLocnTopic then
   ctfws:setTerritory(m)
   ctfws_lcd:drawFlags()
  elseif t:match("^ctfws/game/message") then
    boot_message_hack = nil
    local mt, ms = m:match("^%s*(%d+)%s*(.*)$")
    if mt == nil then -- maybe they forgot a timestamp?
      lastMsgTime = rtctime.get() - 30 -- subtract some wiggle room
      ctfws_lcd:drawMessage(m)
    else
      mt = tonumber(mt)
      if (ctfws.startT == nil or ctfws.startT <= mt)  -- message for this game
         and (lastMsgTime == nil or lastMsgTime < mt) -- latest message (strict)
       then
        lastMsgTime = mt
        ctfws_lcd:drawMessage(ms)
      end
    end
  end
end

-- network callbacks

nwfnet.onnet["init"] = function(e,c)
  dprint("NET", e)
  if     e == "mqttdscn" and c == mqc then
    mqtt_beat_tmr:stop()
    if not mqtt_reconn_cronentry then mqtt_reconn() end
    ctfws_lcd:drawFlagsMessage("MQTT Disconnected")
  elseif e == "mqttconn" and c == mqc then
    if mqtt_reconn_cronentry then mqtt_reconn_cronentry:unschedule() mqtt_reconn_cronentry = nil end
    mqtt_beat_tmr:start()
    mqc:publish(mqttBootTopic,"alive",1,1)
    mqc:subscribe({
      ["ctfws/game/config"] = 2,
      ["ctfws/game/endtime"] = 2,
      ["ctfws/game/flags"] = 2,
      [mqttLocnTopic] = 2,             -- my location
      ["ctfws/game/message"] = 2,      -- broadcast messages
      ["ctfws/game/message/jail"] = 2, -- jail-specific messages
    })
    ctfws_lcd:drawFlagsMessage("MQTT CONNECTED")
  elseif e == "wstagoip"              then
    if not mqtt_reconn_cronentry then mqtt_reconn() end
    ctfws_lcd:drawFlagsMessage(string.format("DHCP %s",c.IP))
  elseif e == "wstaconn"              then
    myBSSID = c.BSSID
    ctfws_lcd:drawFlagsMessage(string.format("WIFI %s",c.SSID))
  elseif e == "sntpsync"              then
    -- If we have a game configuration and just got SNTP sync, it might
    -- be that we just lept far into the future, so go ahead and start
    -- the game!
    if ctfws.startT then ctfws_start_tmr() end
  end
end

-- hook us up to the network!
ctfws_lcd:drawFlagsMessage("CONNECTING...")
-- OVL["nwfnet-diag"]()(true)
OVL["nwfnet-go"]()