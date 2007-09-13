--
-- | The packages methods of ghf.
--

module Ghf.Package (
    packageConfig
,   packageBuild
,   packageDoc
,   packageClean
,   packageCopy
,   packageRun

,   packageInstall
,   packageRegister
,   packageUnregister
,   packageTest
,   packageSdist
,   packageOpenDoc
) where

import Graphics.UI.Gtk
import Graphics.UI.Gtk.ModelView as New
import Control.Monad.Reader
import Data.IORef
import System.IO
import System.FilePath
import System.Environment
import System.Directory
import System.Process
import Distribution.Package
import Distribution.PackageDescription
import Distribution.Simple.Configure
import Distribution.Setup
import Distribution.Program
import Distribution.Simple.LocalBuildInfo
import Distribution.PreProcess
import Distribution.Simple.Build
import Data.Maybe
import Prelude hiding (catch)
import Control.Exception
import Control.Concurrent

import Ghf.Core
import Ghf.Editor.PackageEditor
import Ghf.GUI.Log

getActivePackage :: GhfM (Maybe GhfPackage)
getActivePackage = do
    active <- readGhf activePack
    case active of
        Just p -> return (Just p)
        Nothing -> selectActivePackage

selectActivePackage :: GhfM (Maybe GhfPackage)
selectActivePackage = do
    window  <- readGhf window
    mbFilePath <- lift $choosePackageFile window
    case mbFilePath of
        Nothing -> return Nothing
        Just filePath -> do
            let flags = emptyConfigFlags defaultProgramConfiguration
            packageD <- lift $readPackageDescription filePath
            let pack = GhfPackage (package packageD) filePath [] [] [] [] [] [] [] []
            modifyGhf_ (\ghf -> return (ghf{activePack = (Just pack)}))
            lift $putStrLn $"Set current directory " ++ dropFileName filePath
            lift $setCurrentDirectory $dropFileName filePath
            return (Just pack)

packageConfig :: Bool -> GhfAction
packageConfig force = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","configure"] ++ (configFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageBuild :: Bool -> GhfAction
packageBuild force = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","build"] ++ (buildFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageDoc :: GhfAction
packageDoc = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","haddock"] ++ (haddockFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageClean :: GhfAction
packageClean = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","clean"] ++ (haddockFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageCopy :: GhfAction
packageCopy = do
    mbPackage   <- getActivePackage
    log         <- getLog
    mbDir       <- chooseDir "Select the target directory"
    case mbDir of
        Nothing -> return ()
        Just fp ->
            case mbPackage of
                Nothing         -> return ()
                Just package    -> lift $do
                    (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","copy"] ++ ["--destdir=" ++ fp])
                    oid <- forkIO (readOut log out)
                    eid <- forkIO (readErr log err)
                    return ()

packageRun :: GhfAction
packageRun = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            pd <- readPackageDescription (cabalFile package)
            case executables pd of
                [(Executable name _ _)] -> do
                    let path = "dist/build" </> pkgName (packageId package) </> name
                    (inp,out,err,pid) <- runExternal path (exeFlags package)
                    oid <- forkIO (readOut log out)
                    eid <- forkIO (readErr log err)
                    return ()
                otherwise -> do
                    putStrLn "no single executable in selected package"
                    return ()

packageInstall :: GhfAction
packageInstall = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","install"] ++ (installFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageRegister :: GhfAction
packageRegister = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","register"] ++ (registerFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageUnregister :: GhfAction
packageUnregister = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","unregister"] ++ (unregisterFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageTest :: GhfAction
packageTest = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","test"])
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageSdist :: GhfAction
packageSdist = do
    mbPackage   <- getActivePackage
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            (inp,out,err,pid) <- runExternal "runhaskell" (["Setup","sdist"] ++ (sdistFlags package))
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

packageOpenDoc :: GhfAction
packageOpenDoc = do
    mbPackage   <- getActivePackage
    prefs       <- readGhf prefs
    log         <- getLog
    case mbPackage of
        Nothing         -> return ()
        Just package    -> lift $do
            let path = "dist/doc/html" </> pkgName (packageId package) </> "index.html"
            (inp,out,err,pid) <- runExternal (browser prefs) [path]
            oid <- forkIO (readOut log out)
            eid <- forkIO (readErr log err)
            return ()

chooseDir :: String -> GhfM (Maybe FilePath)
chooseDir str = do
    win <- readGhf window
    lift $do
        dialog <- fileChooserDialogNew
                        (Just $ str)
                        (Just win)
                    FileChooserActionSelectFolder
                    [("gtk-cancel"
                    ,ResponseCancel)
                    ,("gtk-open"
                    ,ResponseAccept)]
        widgetShow dialog
        response <- dialogRun dialog
        case response of
            ResponseAccept -> do
                fn <- fileChooserGetFilename dialog
                widgetDestroy dialog
                return fn
            ResponseCancel -> do
                widgetDestroy dialog
                return Nothing
            ResponseDeleteEvent -> do
                widgetDestroy dialog
                return Nothing

readOut :: GhfLog -> Handle -> IO ()
readOut log hndl =
     catch (readAndShow)
       (\e -> do
        appendLog log ("----------------------------------------\n") FrameTag
        hClose hndl
        return ())
    where
    readAndShow = do
        line <- hGetLine hndl
        appendLog log (line ++ "\n") LogTag
        readAndShow

readErr :: GhfLog -> Handle -> IO ()
readErr log hndl =
     catch (readAndShow)
       (\e -> do
        hClose hndl
        return ())
    where
    readAndShow = do
        line <- hGetLine hndl
        appendLog log (line ++ "\n") ErrorTag
        readAndShow

runExternal :: FilePath -> [String] -> IO (Handle, Handle, Handle, ProcessHandle)
runExternal path args = do
    hndls@(inp, out, err, _) <- runInteractiveProcess path args Nothing Nothing
    putStrLn $ "Starting external tool: " ++ path
    hSetBuffering out NoBuffering
    hSetBuffering err NoBuffering
    hSetBuffering inp NoBuffering
    hSetBinaryMode out True
    hSetBinaryMode err True
    return hndls




