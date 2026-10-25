module Tricorder.MCP.Main (main) where

import Data.Version (showVersion)
import MCP.Server
  ( McpServerHandlers (..),
    McpServerInfo (..),
    noHandlers,
    runMcpServerStdio,
  )
import Paths_tricorder_mcp (version)
import System.IO (hSetEncoding, stdin, stdout, utf8)
import Tricorder.MCP.Derive (deriveCheckedToolHandler)
import Tricorder.MCP.Tools (Tool, handleTool, toolDescriptions)

main :: IO ()
main = do
  -- The mcp-server stdio transport reads stdin via TIO.getLine (handle
  -- encoding), while it pins stdout/stderr to utf8Transliterate internally.
  -- We must pin stdin ourselves so a non-UTF-8 locale does not crash on a
  -- request containing non-ASCII.
  hSetEncoding stdin utf8
  hSetEncoding stdout utf8
  runMcpServerStdio serverInfo handlers

handlers :: McpServerHandlers
handlers =
  noHandlers
    { tools = Just $(deriveCheckedToolHandler ''Tool 'handleTool toolDescriptions)
    }

serverInfo :: McpServerInfo
serverInfo =
  McpServerInfo
    { serverName = "Tricorder MCP Server",
      serverVersion = toText (showVersion version),
      serverInstructions = "A server to manage and use Tricorder for development purposes."
    }
