-- | Regression tests for the CLI entry point's standard-stream handling.
module Unit.Tricorder.CLI.MainSpec (test_Main) where

import Control.Exception (SomeException, finally, fromException, try)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.IO.Encoding (mkTextEncoding)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.Environment (withArgs)
import System.Exit (ExitCode (..))
import System.IO (hClose, hGetEncoding, hSetEncoding, stderr, stdout)
import System.Process (createPipe)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertFailure, testCase, (@?), (@?=))
import Tricorder.CLI.Main qualified as CLI

test_Main :: TestTree
test_Main =
  testCase "renders --help with non-ASCII text under an ASCII-encoded stdout" do
    -- Regression: optparse-applicative renders help as 'String' through the
    -- handle's text encoding. With the locale encoding (e.g. LANG=C), the
    -- em-dashes in the help text crashed with
    -- @commitBuffer: invalid argument (cannot encode character '\8212')@.
    -- The entry point must pin stdout/stderr to UTF-8 first.
    (captureR, captureW) <- createPipe
    savedOut <- hDuplicate stdout
    savedOutEnc <- hGetEncoding stdout
    savedErrEnc <- hGetEncoding stderr
    asciiEnc <- mkTextEncoding "ASCII"
    result <-
      ( do
          hDuplicateTo captureW stdout
          hSetEncoding stdout asciiEnc
          withArgs ["--help"] (try @SomeException CLI.main)
      )
        `finally` do
          hDuplicateTo savedOut stdout
          mapM_ (hSetEncoding stdout) savedOutEnc
          mapM_ (hSetEncoding stderr) savedErrEnc
          hClose savedOut
          hClose captureW
    captured <- BS.hGetContents captureR
    -- Ensure we observe any failure before checking content.
    case result of
      Left ex
        | Just exitCode <- fromException @ExitCode ex -> exitCode @?= ExitSuccess
        | otherwise -> assertFailure ("--help crashed: " <> show ex)
      Right () -> assertFailure "--help returned instead of exiting"
    let decoded = TE.decodeUtf8 captured
    ("tricorder" `T.isInfixOf` decoded)
      @? ("help output was not written: " <> show decoded)
    ("\8212" `T.isInfixOf` decoded)
      @? ("help output lost em-dash; got: " <> show decoded)
