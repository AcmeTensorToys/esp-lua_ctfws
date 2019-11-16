-- fields:
--   dl_* fields are "drawn last", used to avoid writing things that are
--   already correct on screen.  They can be set to nil to force refresh.
--   Certain things (flags, messages) are considered rare enough that we
--   don't cache like this.
--
--     dl_round
--     dl_elapsed
--     dl_remain

local function drawDScond(max, last, decisec, thresh)
  return (max >= thresh) and ((last == nil) or math.floor(last / thresh) ~= math.floor(decisec / thresh))
end

-- Save I2C bandwidth by only drawing what we have to, to some approximation
local function drawDS(lcd, row, col, max, last, decisec)
  -- If we wanted to support hour-long times, we might do something like
  -- this.  As we don't, at the moment...
  -- if drawDScond(max, last, decisec, 36000) then -- hours and all the way down
  --   lcd:put(lcd:locate(row,col), string.format("%02d:%02d:%02d.%d",
  --     decisec/3600, decisec/600, (decisec/10)%60, decisec%10))
  -- else
  if drawDScond(max, last, decisec, 600) then -- minutes, seconds, and deci
      if decisec >= 60000 then
       -- for incredibly long times, just space pad and hope for the best
       lcd:put(lcd:locate(row,col), string.format("% 4d:%02d.%d", decisec/600, (decisec/10)%60, decisec%10))
     else
       lcd:put(lcd:locate(row,col), string.format("  %02d:%02d.%d", decisec/600, (decisec/10)%60, decisec%10))
     end
  elseif drawDScond(max, last, decisec, 10) then -- seconds and deci
     lcd:put(lcd:locate(row,col+5), string.format("%02d.%d", (decisec/10)%60, decisec%10))
  else -- just deci
     lcd:put(lcd:locate(row,col+8), string.format("%d",decisec%10))
  end
end

-- scroll a message msg across line lix using the timer t
local function scroller(lcd, t, lix, msg)
  local mlen = #msg
  if mlen <= 20
   then lcd:put(lcd:locate(lix,(20-mlen)/2),msg)
   else
     -- inspired by lcd:run(), but corrected
     local ix = 1
     local function doscroll()
       if     ix <= 20   then lcd:put(lcd:locate(lix,20-ix),msg:sub(1,ix))
       elseif ix >  mlen then lcd:put(lcd:locate(lix,0),msg:sub(ix-19)," ")
       else                   lcd:put(lcd:locate(lix,0),msg:sub(ix-19,ix))
       end
       if ix >= mlen + 20 then ix = 1 else ix = ix + 1 end
     end
     t:alarm(300, tmr.ALARM_AUTO, doscroll)
  end
end

-- call back `cb` cycling through elements of table `ta` using
-- timer `tm` every `linger` ms.
local function alternator(tm, linger, ta, cb)
  local n = #ta
  local ix = 1
  local function donext()
    cb(ta[ix])
    ix = ix + 1
    if ix > n then ix = 1 end
  end
  donext()
  tm:alarm(linger, tmr.ALARM_AUTO, donext)
end

local function drawNoGame(lcd, msg)
  lcd:put(lcd:locate(0,0), " CMUKGB CTFWS TIMER ")
  lcd:put(lcd:locate(3,0), "                    ")
  lcd:put(lcd:locate(3,(20-#msg)/2), msg)
end

local function drawSteadyTopLine(self,gn,rix,maxt,ela)
  local lcd = self.lcd
  local ctfws = self.ctfws
  if self.dl_elapsed == nil then
    lcd:put(lcd:locate(0,0), "                    ")
    local str
    if gn == nil or gn == 0 then
        if rix == 0 then str = ("SETUP")
        else             str = ("GAME")
        end
    elseif rix == 0 then str = ("SETUP G%d"):format(gn)
    else                 str = ("GAME %d"):format(gn)
    end
    lcd:put(lcd:locate(0,0), str)
    lcd:put(lcd:locate(0,10), (self.connected and ":") or "?")
  end
  drawDS(lcd,0,11,maxt,self.dl_elapsed,ela); self.dl_elapsed = ela
end

local function drawSteadyBotLine(self,rix,maxt,rem)
  local lcd = self.lcd
  local ctfws = self.ctfws
  if self.dl_remain == nil then
    lcd:put(lcd:locate(3,0), "                    ")
    if rix == 0 then
      lcd:put(lcd:locate(3,0), "START IN")
    elseif rix < ctfws.rounds then
      if ctfws.rounds >= 11
        then lcd:put(lcd:locate(3,0), string.format("JB %2d/%2d IN",rix,ctfws.rounds-1))
        else lcd:put(lcd:locate(3,0), string.format("JB %d/%d IN",rix,ctfws.rounds-1))
      end
    else
      lcd:put(lcd:locate(3,0), "GAME END IN")
    end
  end
  drawDS(lcd,3,11,maxt,self.dl_remain ,rem); self.dl_remain  = rem
end

local function attention(self,long)
  if self.attnState then return end

  local lcd = self.lcd

  local function doBlink()
    if self.attnState <= 0 then
      self.attnState = nil
      gpio.write(5,gpio.HIGH) -- silence beeper always
      return
    end
    self.attnState = self.attnState - 1
    -- blink
    lcd:light(false)
    tmr.create():alarm(250,tmr.ALARM_SINGLE,
      function() lcd:light(true) ; (tmr.create()):alarm(500,tmr.ALARM_SINGLE,doBlink) end)
    -- chirp or scream
    gpio.write(5,gpio.LOW)
    if not long then tmr.create():alarm(100, tmr.ALARM_SINGLE, function() gpio.write(5,gpio.HIGH) end) end
  end

  self.attnState = 2
  (tmr.create()):alarm(250, tmr.ALARM_SINGLE, doBlink)
end

-- returns true if timers should keep going or false if we should wait for
-- the next message or event
local function drawTimes(self)
  local ctfws = self.ctfws
  local rix, roundD, roundEla, gameEla = ctfws:times(rtctime.get)
  if rix == nil then
    drawNoGame(self.lcd, roundD)
    if rix ~= self.dl_round then
      self.dl_round = rix
      attention(self,true)
    end
    return false
  end
  if rix ~= self.dl_round then
    if self.dl_round ~= nil then attention(self,true) end
    self.dl_round = rix
    self.dl_elapsed = nil -- force redraws of times on round boundaries
    self.dl_remain  = nil
  end
  drawSteadyTopLine(self,ctfws.gamenr,rix,roundD,gameEla)
  drawSteadyBotLine(self,rix,roundD,roundD-roundEla)
  return true
end

local function drawFlags(self)
  local ctfws = self.ctfws
  if ctfws.flagsN then -- try not to blank a flagsmessage unless we have reason
    self.ftmr:unregister()
    self.fatmr:unregister()
    lcd:put(lcd:locate(1,0),"                    ")
  end
  if ctfws.startT then
    local rc, yc = "r", "y"
    (({ ['r'] = function() rc = 'R' end,
        ['y'] = function() yc = 'Y' end
    })[ctfws:myTeam()] or function() end)()
    local oneline = string.format("%d\000: %s=%s %s=%s",
                      ctfws.flagsN,
                      rc, tostring(ctfws.flagsR),
                      yc, tostring(ctfws.flagsY))
    if #oneline <= 20 then
      lcd:put(lcd:locate(1,(20-#oneline)/2),oneline)
    else
      local fr = tostring(ctfws.flagsR)
      local fy = tostring(ctfws.flagsY)
      local fn = tostring(ctfws.flagsN)
      local maxl = math.max(#fr, #fy)
      if maxl + #fn + 5 <= 20 then
        alternator(self.fatmr, 2000,
          { string.format("%d\000: %s=%s%s", fn, rc, string.rep(" ", maxl-#fr), fr)
          , string.format("%d\000: %s=%s%s", fn, yc, string.rep(" ", maxl-#fy), fy)
          },
          function(msg) lcd:put(lcd:locate(1,(20-#msg)/2),msg) end)
       else
        -- The judges have clearly gone insane; just scroll the long line.
        -- We don't scroll within the alternator above because who knows,
        -- at this point, how long these lines are and maybe they'd
        -- temporarily render blank.
        scroller(self.lcd, self.ftmr, 1, oneline)
      end
    end
    attention(self,false)
  end
end

-- Displays only when the game is not configured; useful for initial
-- boot, perhaps.
local function drawFlagsMessage(self, msg)
  if self.ctfws.flagsN then return end -- NOP on game configured
  lcd:put(lcd:locate(1,0),string.format("%-20s", msg:sub(1,20)))
end

local function drawMessage(self, msg)
  -- blank and stop scrolling
  self.mtmr:unregister()
  lcd:put(lcd:locate(2,0),"                    ")

  if not msg then return end

  scroller(self.lcd, self.mtmr, 2, msg)
  attention(self,false)
end

local function reset(self)
  self.dl_elapsed = nil
  self.dl_remain  = nil
  self.dl_round   = nil
end

return function(ctfws, lcd, mt, ft, fa)
  local self = {}
  self.ctfws = ctfws
  self.lcd = lcd
  self.mtmr = mt
  self.ftmr = ft
  self.fatmr = fa

  self.attnState        = nil

  self.reset            = reset
  self.drawTimes        = drawTimes
  self.drawFlags        = drawFlags
  self.drawMessage      = drawMessage
  self.drawFlagsMessage = drawFlagsMessage

  -- load custom flag glyph
  lcd:define_char(0,{ 0x1F, 0x15, 0x1B, 0x15, 0x1F, 0x10, 0x10, 0x0 })

  return self
end
