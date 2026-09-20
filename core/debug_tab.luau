-- The whole debug tab, in one place, so a prod build drops it by simply not
-- calling this.
--
-- Everything in here works on any Roblox place: dump the remotes, dump
-- whatever GUI is on screen, decompile the client scripts, log what the
-- player interacts with, and the movement helpers. Nothing knows or cares
-- which game it's running in - the game-specific probes that used to live
-- alongside these (dump the chest, read this game's state table, inspect
-- this game's buttons) had all served their purpose and are gone.
--
-- Imports happen inside this module rather than in main.luau, because a
-- prod bundle omits core/debug_* entirely and a top-level import of a
-- missing module would be a hard error.
return function(import)

local interactionLogger = import("core/debug_interaction_logger")(import)
local dumpRemotes = import("core/debug_dump_remotes")(import)
local dumpGui = import("core/debug_dump_gui")(import)
local decompileScripts = import("core/debug_decompile")(import)
local humanoid = import("core/humanoid")

-- `persist` carries main.luau's Toggle/Slider helpers so these controls are
-- remembered across reloads exactly like the farm ones.
local function build(window, persist)
    local tab = window:AddTab("ดีบัก", "🐛")

    persist.Toggle(
        tab:AddCard(
            "Interaction Logger",
            "เปิดแล้วไปกด/แตะอะไรก็ได้ในเกม ทุก prompt/click/ปุ่มจะถูกบันทึกลง MekPro.log"
        ),
        "interactionLogger",
        interactionLogger.SetEnabled
    )

    -- Forward-declared buttons throughout: the callback closes over the
    -- button, and a `local b = AddButton(..., function() b... end)` in one
    -- statement would have the closure see the OUTER (nil) b - the new
    -- local's scope doesn't start until after the whole statement ends.
    local remoteCard = tab:AddCard(
        "Dump All Remotes",
        "บันทึกรายชื่อ RemoteEvent/RemoteFunction ทั้งหมดใน ReplicatedStorage ลง MekPro.log"
    )
    local remoteBtn
    remoteBtn = remoteCard:AddButton("Dump", function()
        remoteBtn.Text = dumpRemotes() .. " remotes"
    end)

    local guiCard = tab:AddCard(
        "Dump Visible GUI",
        "เปิดหน้าจอที่อยากดูค้างไว้ก่อน แล้วกดปุ่มนี้ - ไล่ทุก ScreenGui ที่เปิดอยู่"
    )
    local guiBtn
    guiBtn = guiCard:AddButton("Dump", function()
        guiBtn.Text = dumpGui() .. " screens"
    end)

    -- The single most useful tool in the hub: it's what turned every "why
    -- doesn't this work" into a read of the game's actual source.
    local decompileCard = tab:AddCard(
        "Decompile Client Scripts",
        "เช็คความสามารถของ executor แล้ว decompile ทุก script ใน PlayerScripts ลงไฟล์"
    )
    local decompileBtn
    decompileBtn = decompileCard:AddButton("Run", function()
        decompileBtn.Text = decompileScripts() .. " files"
    end)

    -- Movement helpers: game-agnostic, but the most visible thing the hub
    -- can do, which is the other reason they sit behind the debug flag.
    humanoid.Start()

    persist.Slider(tab, "ความเร็ววิ่ง", "WalkSpeed (ปกติ 16)",
        8, 200, "walkSpeed", 16, humanoid.SetWalkSpeed, "")
    persist.Slider(tab, "แรงกระโดด", "JumpPower (ปกติ 50)",
        30, 300, "jumpPower", 50, humanoid.SetJumpPower, "")

    persist.Toggle(
        tab:AddCard("บิน (Fly)", "บินด้วย WASD + Space/Ctrl ตามทิศกล้อง"),
        "fly", humanoid.SetFlying
    )
    persist.Toggle(
        tab:AddCard("มุดแมพ (Noclip)", "เดินทะลุกำแพงและพื้น"),
        "noclip", humanoid.SetNoclip
    )
    persist.Toggle(
        tab:AddCard("ลอย (Float)", "ล็อกความสูงไว้ที่ระดับปัจจุบัน"),
        "float", humanoid.SetFloating
    )

    -- Handed back so the caller's teardown can stop these loops; leaving
    -- them running after the menu closes makes them invisible AND
    -- uncontrollable.
    return function()
        interactionLogger.SetEnabled(false)
        humanoid.Stop()
    end
end

return build

end
