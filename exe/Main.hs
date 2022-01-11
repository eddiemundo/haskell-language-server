-- Copyright (c) 2019 The DAML Authors. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
module Main(main) where

import           Data.Function                ((&))
import           Development.IDE.Types.Logger (Priority (Debug, Info),
                                               WithPriority (WithPriority, priority),
                                               cfilter, cmap,
                                               withDefaultRecorder)
import qualified Development.IDE.Types.Logger as Logger
import           Ide.Arguments                (Arguments (..),
                                               GhcideArguments (..),
                                               getArguments)
import           Ide.Main                     (defaultMain)
import qualified Ide.Main                     as IdeMain
import qualified Plugins
import           Prettyprinter                (Doc, Pretty (pretty))
import qualified System.Log                   as HsLogger

data Log
  = LogIdeMain IdeMain.Log
  | LogPlugins Plugins.Log
  deriving Show

instance Pretty Log where
  pretty log = case log of
    LogIdeMain ideMainLog -> pretty ideMainLog
    LogPlugins pluginsLog -> pretty pluginsLog

logToPriority :: Log -> Logger.Priority
logToPriority = \case
  LogIdeMain log -> IdeMain.logToPriority log
  LogPlugins log -> Plugins.logToPriority log

logToDocWithPriority :: Log -> WithPriority (Doc a)
logToDocWithPriority log = WithPriority (logToPriority log) (pretty log)

main :: IO ()
main = do
    -- passing mempty for recorder to idePlugins means that any custom cli
    -- command provided by a plugin will not have logging powers
    args <- getArguments "haskell-language-server" (Plugins.idePlugins mempty False)

    let (hsLoggerMinPriority, minPriority, logFilePath, includeExamplePlugins) =
          case args of
            Ghcide GhcideArguments{ argsTesting, argsDebugOn, argsLogFile, argsExamplePlugin } ->
              let (minHsLoggerPriority, minPriority) =
                    if argsDebugOn || argsTesting then (HsLogger.DEBUG, Debug) else (HsLogger.INFO, Info)
              in (minHsLoggerPriority, minPriority, argsLogFile, argsExamplePlugin)
            _ -> (HsLogger.INFO, Info, Nothing, False)

    withDefaultRecorder logFilePath hsLoggerMinPriority $ \textWithPriorityRecorder -> do
      let recorder =
            textWithPriorityRecorder
            & cfilter (\WithPriority{ priority } -> priority >= minPriority)
            & cmap logToDocWithPriority

      defaultMain (cmap LogIdeMain recorder) args (Plugins.idePlugins (cmap LogPlugins recorder) includeExamplePlugins)
