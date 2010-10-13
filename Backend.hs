{- git-annex key/value storage backends
 -
 - git-annex uses a key/value abstraction layer to allow files contents to be
 - stored in different ways. In theory, any key/value storage system could be
 - used to store the file contents, and git-annex would then retrieve them
 - as needed and put them in `.git/annex/`.
 - 
 - When a file is annexed, a key is generated from its content and/or metadata.
 - This key can later be used to retrieve the file's content (its value). This
 - key generation must be stable for a given file content, name, and size.
 - 
 - Multiple pluggable backends are supported, and more than one can be used
 - to store different files' contents in a given repository.
 - -}

module Backend (
	lookupBackend,
	storeFile,
	retrieveFile,
	fileKey,
	dropFile
) where

import System.Directory
import System.FilePath
import Data.String.Utils
import System.Posix.Files
import Locations
import GitRepo
import Utility
import Types

{- Attempts to store a file in one of the backends. -}
storeFile :: State -> FilePath -> IO (Maybe (Key, Backend))
storeFile state file = storeFile' (backends state) state file
storeFile' [] _ _ = return Nothing
storeFile' (b:bs) state file = do
	try <- (getKey b) state (gitRelative (repo state) file)
	case (try) of
		Nothing -> nextbackend
		Just key -> do
			stored <- (storeFileKey b) state file key
			if (not stored)
				then nextbackend
				else do
					return $ Just (key, b)
	where
		nextbackend = storeFile' bs state file

{- Attempts to retrieve an file from one of the backends, saving it to
 - a specified location. -}
retrieveFile :: State -> FilePath -> FilePath -> IO Bool
retrieveFile state file dest = do
	result <- lookupBackend state file
	case (result) of
		Nothing -> return False
		Just backend -> do
			key <- fileKey file
			(retrieveKeyFile backend) state key dest

{- Drops the key for a file from the backend that has it. -}
dropFile :: State -> FilePath -> IO (Maybe (Key, Backend))
dropFile state file = do
	result <- lookupBackend state file
	case (result) of
		Nothing -> return Nothing
		Just backend -> do
			key <- fileKey file
			(removeKey backend) state key
			return $ Just (key, backend)

{- Looks up the backend used for an already annexed file. -}
lookupBackend :: State -> FilePath -> IO (Maybe Backend)
lookupBackend state file = lookupBackend' (backends state) state file
lookupBackend' [] _ _ = return Nothing
lookupBackend' (b:bs) state file = do
	present <- checkBackend b state file
	if present
		then
			return $ Just b
		else
			lookupBackend' bs state file

{- Checks if a file is available via a given backend. -}
checkBackend :: Backend -> State -> FilePath -> IO (Bool)
checkBackend backend state file = 
	doesFileExist $ annexLocation state backend file

{- Looks up the key corresponding to an annexed file,
 - by examining what the file symlinks to. -}
fileKey :: FilePath -> IO Key
fileKey file = do
	l <- readSymbolicLink (file)
	return $ takeFileName $ l
