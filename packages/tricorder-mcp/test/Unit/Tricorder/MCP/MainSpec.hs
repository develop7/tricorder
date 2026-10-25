-- | Regression tests for the MCP server entry point's standard-stream handling.
module Unit.Tricorder.MCP.MainSpec (test_Main) where

import Control.Exception (SomeException, finally, try)
import Data.List (isInfixOf)
import GHC.IO.Encoding (mkTextEncoding)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.Directory (removeFile)
import System.IO (SeekMode (..), hClose, hFlush, hGetEncoding, hPutStr, hSeek, hSetEncoding, openTempFile, readFile, stdin, stdout, utf8)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertFailure, testCase, (@?))
import Tricorder.MCP.Main qualified as MCP

test_Main :: TestTree
test_Main =
  testCase "serves a non-ASCII JSON-RPC request under an ASCII-encoded stdin" do
    -- Regression: @mcp-server@'s stdio transport reads stdin via
    -- 'Data.Text.IO.getLine', i.e. through the handle's text encoding.
    -- Under a non-UTF-8 locale, a request containing non-ASCII text (here
    -- in @clientInfo@) crashed the server with a decode error. The entry
    -- point must pin stdin to UTF-8 first (the transport already pins
    -- stdout/stderr itself).
    (inPath, inH) <- openTempFile "/tmp" "tricorder-mcp-stdin"
    (outPath, outH) <- openTempFile "/tmp" "tricorder-mcp-stdout"
    hSetEncoding inH utf8
    hPutStr inH requestJson
    hFlush inH
    hSeek inH AbsoluteSeek 0
    savedIn <- hDuplicate stdin
    savedOut <- hDuplicate stdout
    savedInEnc <- hGetEncoding stdin
    savedOutEnc <- hGetEncoding stdout
    asciiEnc <- mkTextEncoding "ASCII"
    result <-
      ( do
          hDuplicateTo inH stdin
          hSetEncoding stdin asciiEnc
          hDuplicateTo outH stdout
          try @SomeException MCP.main
      )
        `finally` do
          hDuplicateTo savedIn stdin
          hDuplicateTo savedOut stdout
          mapM_ (hSetEncoding stdin) savedInEnc
          mapM_ (hSetEncoding stdout) savedOutEnc
          hClose savedIn
          hClose savedOut
          hClose inH
          hClose outH
    captured <- readFile outPath
    length captured `seq` removeFile inPath
    removeFile outPath
    case result of
      Left ex -> assertFailure ("tricorder-mcp crashed: " <> show ex)
      Right () -> pure ()
    -- A response proves the request was decoded and dispatched.
    ("\"jsonrpc\"" `isInfixOf` captured)
      @? "no JSON-RPC response was written for the request"

-- | A well-formed @initialize@ request whose @clientInfo.name@ is non-ASCII.
requestJson :: String
requestJson =
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"tëst\",\"version\":\"1.0\"}}}\n"
