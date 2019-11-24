-- updated to handle both immediate evaluation when pulling data from pss (doesnt require invoking calls to loadreplay data) and scoretab plot construction (does) -mina

local judges = {"marv", "perf", "great", "good", "boo", "miss"}
local tst = ms.JudgeScalers
local judge = GetTimingDifficulty()
local tso = tst[judge]

local enabledCustomWindows = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomEvaluationWindowTimings
judge = enabledCustomWindows and 0 or judge
local customWindowsData = timingWindowConfig:get_data()
local customWindows = timingWindowConfig:get_data().customWindows
local customWindow = timingWindowConfig:get_data()[customWindows[1]]

local plotWidth, plotHeight = 400, 120
local plotX, plotY = SCREEN_WIDTH - 9 - plotWidth / 2, SCREEN_HEIGHT - 56 - plotHeight / 2
local dotDims, plotMargin = 2, 4
local maxOffset = math.max(180, 180 * tso)
local baralpha = 0.2
local bgalpha = 0.8
local textzoom = 0.35

local translated_info = {
	Left = THEME:GetString("OffsetPlot", "ExplainLeft"),
	Right = THEME:GetString("OffsetPlot", "ExplainRight"),
	Down = THEME:GetString("OffsetPlot", "ExplainDown"),
	Early = THEME:GetString("OffsetPlot", "Early"),
	Late = THEME:GetString("OffsetPlot", "Late")
}

-- initialize tables we need for replay data here, we don't know where we'll be loading from yet
local dvt = {}
local nrt = {}
local ctt = {}
local ntt = {}
local wuab = {}
local finalSecond = GAMESTATE:GetCurrentSong(PLAYER_1):GetLastSecond()
local td = GAMESTATE:GetCurrentSteps(PLAYER_1):GetTimingData()

local handspecific = false
local left = false

local function fitX(x) -- Scale time values to fit within plot width.
	if finalSecond == 0 then
		return 0
	end
	return x / finalSecond * plotWidth - plotWidth / 2
end

local function fitY(y) -- Scale offset values to fit within plot height
	return -1 * y / maxOffset * plotHeight / 2
end

local function HighlightUpdaterThing(self)
	self:GetChild("BGQuad"):queuecommand("Highlight")
end

-- convert a plot x position to a noterow
local function convertXToRow(x)
	local output = x + plotWidth/2
	output = output / plotWidth

	if output < 0 then output = 0 end
	if output > 1 then output = 1 end

	-- the 48 here is how many noterows there are per beat
	-- this is a const defined in the game
	-- and i sure hope it doesnt ever change
	local td = GAMESTATE:GetCurrentSteps():GetTimingData()
	local row = td:GetBeatFromElapsedTime(output * finalSecond) * 48

	return row
end

local o =
	Def.ActorFrame {
	OnCommand = function(self)
		self:xy(plotX, plotY)

		-- being explicit about the logic since atm these are the only 2 cases we handle
		local name = SCREENMAN:GetTopScreen():GetName()
		if name == "ScreenEvaluationNormal" or name == "ScreenNetEvaluation" then -- default case, all data is in pss and no disk load is required
			self:SetUpdateFunction(HighlightUpdaterThing)
			local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(PLAYER_1)
			dvt = pss:GetOffsetVector()
			nrt = pss:GetNoteRowVector()
			ctt = pss:GetTrackVector() -- column information for each offset
			ntt = pss:GetTapNoteTypeVector() -- notetype information (we use this to handle mine hits differently- currently that means not displaying them)
		elseif name == "ScreenScoreTabOffsetPlot" then -- loaded from scoretab not eval so we need to read from disk and adjust plot display
			plotWidth, plotHeight = SCREEN_WIDTH, SCREEN_WIDTH * 0.3
			self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
			textzoom = 0.5
			bgalpha = 1

			-- the internals here are really inefficient this should be handled better (internally) -mina
			local score = getScoreForPlot()
			dvt = score:GetOffsetVector()
			nrt = score:GetNoteRowVector()
			ctt = score:GetTrackVector()
			ntt = score:GetTapNoteTypeVector()
		end

		-- missing noterows. this happens with many online replays.
		-- we can approximate, but i dont want to do that right now.
		if nrt == nil then
			ms.ok("While constructing the offset plot, an error occurred. Press ESC to continue.")
			return
		end

		-- Convert noterows to timestamps and plot dots (this is important it determines plot x values!!!)
		for i = 1, #nrt do
			wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i])
		end
		MESSAGEMAN:Broadcast("JudgeDisplayChanged") -- prim really handled all this much more elegantly
	end,
	CodeMessageCommand = function(self, params)
		if enabledCustomWindows then
			if params.Name == "PrevJudge" then
				judge = judge < 2 and #customWindows or judge - 1
				customWindow = timingWindowConfig:get_data()[customWindows[judge]]
			elseif params.Name == "NextJudge" then
				judge = judge == #customWindows and 1 or judge + 1
				customWindow = timingWindowConfig:get_data()[customWindows[judge]]
			end
		elseif params.Name == "PrevJudge" and judge > 1 then
			judge = judge - 1
			tso = tst[judge]
		elseif params.Name == "NextJudge" and judge < 9 then
			judge = judge + 1
			tso = tst[judge]
		elseif params.Name == "ToggleHands" and #ctt > 0 then --super ghetto toggle -mina
			if not handspecific then
				handspecific = true
				left = true
			elseif handspecific and left then
				left = false
			elseif handspecific and not left then
				handspecific = false
			end
			MESSAGEMAN:Broadcast("JudgeDisplayChanged")
		end
		if params.Name == "ResetJudge" then
			judge = enabledCustomWindows and 0 or GetTimingDifficulty()
			tso = tst[GetTimingDifficulty()]
		end
		maxOffset = (enabledCustomWindows and judge ~= 0) and customWindow.judgeWindows.boo or math.max(180, 180 * tso)
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	UpdateNetEvalStatsMessageCommand = function(self) -- i haven't updated or tested neteval during last round of work -mina
		local s = SCREENMAN:GetTopScreen():GetHighScore()
		if s then
			score = s
			dvt = score:GetOffsetVector()
			nrt = score:GetNoteRowVector()
			ctt = score:GetTrackVector()
			for i = 1, #nrt do
				wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i])
			end
		end
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end
}
-- Background
o[#o + 1] =
	Def.Quad {
	Name = "BGQuad",
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(plotWidth + plotMargin, plotHeight + plotMargin):diffuse(color("0.05,0.05,0.05,0.05")):diffusealpha(
			bgalpha
		)
	end,
	HighlightCommand = function(self)
		local bar = self:GetParent():GetChild("PosBar")
		local txt = self:GetParent():GetChild("PosText")
		if isOver(self) then
			local xpos = INPUTFILTER:GetMouseX() - self:GetParent():GetX()
			local ypos = INPUTFILTER:GetMouseY() - self:GetParent():GetY()
			bar:visible(true)
			txt:visible(true)
			bar:x(xpos)
			txt:x(xpos - 4)
			txt:y(ypos)
			local row = convertXToRow(xpos)
			local judgments = SCREENMAN:GetTopScreen():GetReplaySnapshotJudgmentsForNoterow(row)
			local wifescore = SCREENMAN:GetTopScreen():GetReplaySnapshotWifePercentForNoterow(row) * 100
			local marvCount = judgments[10]
			local perfCount = judgments[9]
			local greatCount = judgments[8]
			local goodCount = judgments[7]
			local badCount = judgments[6]
			local missCount = judgments[5]

			--txt:settextf("x %f\nrow %f\nbeat %f\nfinalsecond %f", xpos, row, row/48, finalSecond)
			txt:settextf("%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %f", "Marvelous", marvCount, "Perfect", perfCount, "Great", greatCount, "Good", goodCount, "Bad", badCount, "Miss", missCount, "WifePercent", wifescore)
		else
			bar:visible(false)
			txt:visible(false)
		end
	end
}
-- Center Bar
o[#o + 1] =
	Def.Quad {
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment("TapNoteScore_W1")):diffusealpha(baralpha)
	end
}
local fantabars = {22.5, 45, 90, 135}
local bantafars = {"TapNoteScore_W2", "TapNoteScore_W3", "TapNoteScore_W4", "TapNoteScore_W5"}
for i = 1, #fantabars do
	o[#o + 1] =
		Def.Quad {
		JudgeDisplayChangedMessageCommand = function(self)
			self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment(bantafars[i])):diffusealpha(baralpha)
			local fit = (enabledCustomWindows and judge ~= 0) and customWindow.judgeWindows[judges[i]] or tso * fantabars[i]
			self:y(fitY(fit))
		end
	}
	o[#o + 1] =
		Def.Quad {
		JudgeDisplayChangedMessageCommand = function(self)
			self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment(bantafars[i])):diffusealpha(baralpha)
			local fit = (enabledCustomWindows and judge ~= 0) and customWindow.judgeWindows[judges[i]] or tso * fantabars[i]
			self:y(fitY(-fit))
		end
	}
end

-- Bar for current mouse position on graph
o[#o + 1] = Def.Quad {
	Name = "PosBar",
	InitCommand = function(self)
		self:visible(false)
		self:zoomto(2, plotHeight + plotMargin):diffuse(color("0.5,0.5,0.5,1"))
	end,
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(2, plotHeight + plotMargin)
	end
}

local dotWidth = dotDims / 2
local function setOffsetVerts(vt, x, y, c)
	vt[#vt + 1] = {{x - dotWidth, y + dotWidth, 0}, c}
	vt[#vt + 1] = {{x + dotWidth, y + dotWidth, 0}, c}
	vt[#vt + 1] = {{x + dotWidth, y - dotWidth, 0}, c}
	vt[#vt + 1] = {{x - dotWidth, y - dotWidth, 0}, c}
end
o[#o + 1] =
	Def.ActorMultiVertex {
	JudgeDisplayChangedMessageCommand = function(self)
		local verts = {}
		for i = 1, #dvt do
			local x = fitX(wuab[i])
			local y = fitY(dvt[i])
			local fit = (enabledCustomWindows and judge ~= 0) and customWindow.judgeWindows.boo + 3 or math.max(183, 183 * tso)
			local cullur =
				(enabledCustomWindows and judge ~= 0) and customOffsetToJudgeColor(dvt[i], customWindow.judgeWindows) or
				offsetToJudgeColor(dvt[i], tst[judge])
			if math.abs(y) > plotHeight / 2 then
				y = fitY(fit)
			end

			-- remember that time i removed redundancy in this code 2 days ago and then did this -mina
			if ntt[i] ~= "TapNoteType_Mine" then
				if handspecific and left then
					if ctt[i] == 0 or ctt[i] == 1 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, offsetToJudgeColorAlpha(dvt[i], tst[judge])) -- highlight left
					end
				elseif handspecific then
					if ctt[i] == 2 or ctt[i] == 3 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, offsetToJudgeColorAlpha(dvt[i], tst[judge])) -- highlight right
					end
				else
					setOffsetVerts(verts, x, y, cullur)
				end
			end
		end
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end
}

-- filter
o[#o + 1] =
	LoadFont("Common Normal") ..
	{
		JudgeDisplayChangedMessageCommand = function(self)
			self:xy(0, plotHeight / 2 - 2):zoom(textzoom):halign(0.5):valign(1)
			if #ntt > 0 then
				if handspecific then
					if left then
						self:settext(translated_info["Left"])
					else
						self:settext(translated_info["Right"])
					end
				else
					self:settext(translated_info["Down"])
				end
			else
				self:settext("")
			end
		end
	}

-- Early/Late markers
o[#o + 1] =
	LoadFont("Common Normal") ..
	{
		JudgeDisplayChangedMessageCommand = function(self)
			self:xy(-plotWidth / 2, -plotHeight / 2 + 2):zoom(textzoom):halign(0):valign(0):settextf("%s (+%ims)", translated_info["Late"], maxOffset)
		end
	}
o[#o + 1] =
	LoadFont("Common Normal") ..
	{
		JudgeDisplayChangedMessageCommand = function(self)
			self:xy(-plotWidth / 2, plotHeight / 2 - 2):zoom(textzoom):halign(0):valign(1):settextf("%s (-%ims)", translated_info["Early"], maxOffset)
		end
	}

-- Text for judgments at mouse position
o[#o + 1] = 
	LoadFont("Common Normal") ..
	{
		Name = "PosText",
		InitCommand = function(self)
			self:x(8):valign(1):halign(1):zoom(0.4)
		end
	}

-- Text for current judge window
-- Only for SelectMusic (not Eval)
o[#o + 1] = 
	LoadFont("Common Normal") ..
	{
		Name = "JudgeText",
		InitCommand = function(self)
			self:valign(0):halign(0):zoom(0.4)
			self:xy(-plotWidth/2, -plotHeight/2)
			self:settext("")
		end,
		OnCommand = function(self)
			local name = SCREENMAN:GetTopScreen():GetName()
			if name == "ScreenScoreTabOffsetPlot" then
				self:playcommand("Set")
			else
				self:visible(false)
			end
		end,
		SetCommand = function(self)
			if enabledCustomWindows then
				jdgname = customWindow.name
			else
				jdgname = "J" .. judge
			end
			self:settextf("%s", jdgname)
		end,
		JudgeDisplayChangedMessageCommand = function(self)
			self:playcommand("Set")
			self:xy(-plotWidth / 2 + 5, -plotHeight / 2 + 15):zoom(textzoom):halign(0):valign(0)
		end
	}

return o
