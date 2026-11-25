"""Exercise atomic saves and bounded backup rotation against temporary files."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

if lupa_path := os.environ.get("RSDW_LUPA_PATH"):
    sys.path.insert(0, lupa_path)
try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    LuaRuntime = None

SCRIPTS = Path(__file__).resolve().parents[2] / "Scripts"


@unittest.skipIf(LuaRuntime is None, "lupa is not installed")
class StoreTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.backups = self.root / "backups"
        self.backups.mkdir()

    def open_store(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().SCRIPT_ROOT = SCRIPTS.as_posix()
        lua.globals().PATH_SEPARATOR = os.sep
        lua.execute(r"""
            package.path = SCRIPT_ROOT .. "/?.lua;" .. package.path
            local function native_path(path)
                return (path:gsub("\\", PATH_SEPARATOR))
            end
            local open, rename, remove = io.open, os.rename, os.remove
            io.open = function(path, mode) return open(native_path(path), mode) end
            io.popen = function() error("shell launched during store save") end
            os.remove = function(path) return remove(native_path(path)) end
            os.rename = function(from, to)
                if from:match("%.tmp$") and to:match(FAILED_TARGET or "^$") then
                    return nil, "injected rename failure"
                end
                return rename(native_path(from), native_path(to))
            end
            WARNINGS = {}
            package.loaded.rlm_log = {
                info = function() end,
                warn = function(message) WARNINGS[#WARNINGS + 1] = message end,
            }
            STORE = require("rlm_store")
        """)
        paths = {"settings": str(self.root / "settings.json"), "user_root": str(self.root)}
        paths["backups"] = str(self.backups)
        store = lua.globals().STORE
        ok, _ = store.initialize(lua.table_from(paths), lua.table(version="test"))
        self.assertTrue(ok)
        return lua, store

    def test_rotation_resumes_after_restart_and_keeps_legacy_backup(self):
        legacy = self.backups / "settings-20261124-190000.json"
        legacy.write_text("archived document", encoding="utf-8")
        active = self.root / "settings.json"
        active.write_text('{"schemaVersion":1,"revision":0}', encoding="utf-8")
        _, store = self.open_store()
        for revision in range(1, 11):
            store.get("settings")["revision"] = revision
            self.assertTrue(store.save("settings")[0])

        _, store = self.open_store()
        for revision in range(11, 17):
            store.get("settings")["revision"] = revision
            self.assertTrue(store.save("settings")[0])

        slots = list(self.backups.glob("settings-rolling-*.json"))
        self.assertEqual(len(slots), 12)
        revisions = sorted(json.loads(slot.read_text(encoding="utf-8"))["revision"] for slot in slots)
        self.assertEqual(revisions, list(range(4, 16)))
        self.assertEqual(json.loads(active.read_text(encoding="utf-8"))["revision"], 16)
        self.assertEqual(legacy.read_text(encoding="utf-8"), "archived document")
        self.assertFalse(list(self.backups.glob("*.json.previous")))

    def test_failed_backup_replacement_preserves_slot_and_still_saves_document(self):
        lua, store = self.open_store()
        target = self.backups / "settings-rolling-01.json"
        target.write_text('{"schemaVersion":1,"revision":-1}', encoding="utf-8")
        lua.globals().FAILED_TARGET = "settings%-rolling%-01%.json$"
        store.get("settings")["revision"] = 1
        self.assertTrue(store.save("settings")[0])
        self.assertEqual(json.loads(target.read_text(encoding="utf-8"))["revision"], -1)
        self.assertEqual(json.loads((self.root / "settings.json").read_text(encoding="utf-8"))["revision"], 1)
        self.assertIn("could not create settings backup", lua.globals().WARNINGS[1])
        self.assertFalse((self.backups / "settings-rolling.next").exists())

    def test_module_owned_document_rotates_its_own_backups(self):
        lua, store = self.open_store()
        self.assertTrue(store.register("gear_swaps", lua.table(file="gear-swaps.json"))[0])
        store.get("gear_swaps")["revision"] = 1
        self.assertTrue(store.save("gear_swaps")[0])
        self.assertTrue((self.backups / "gear_swaps-rolling-01.json").is_file())
        self.assertFalse(list(self.backups.glob("settings-rolling-*.json")))
