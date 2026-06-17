{-# LANGUAGE OverloadedStrings #-}

-- | Emit a representative API's OpenAPI 3.1 document as JSON to stdout.
--
-- Used to feed Layer-3 (external, authoritative) validation:
--
-- > cabal run gen-openapi > openapi.json
-- > nix run nixpkgs#vacuum-go -- lint -d openapi.json
--
-- The document is deliberately a complete OpenAPI 3.1 contract — it carries
-- @info@ (title/version/description), a @server@, @tags@, and a unique
-- @operationId@ per operation — so an external linter has a realistic document
-- to validate rather than the bare skeleton @toOpenApi@ produces by default.
module Main (main) where

import           Control.Lens
import           Data.Aeson                 (ToJSON, encode)
import qualified Data.ByteString.Lazy.Char8 as BL
import           Data.Char                  (isAlphaNum, toUpper)
import           Data.OpenApi               (ToSchema)
import qualified Data.OpenApi               as O
import           Data.Proxy                 (Proxy (..))
import qualified Data.Text                  as T
import           Data.Text                  (Text)
import           GHC.Generics               (Generic)
import           Servant.API
import           Servant.OpenApi            (toOpenApi)

-- A small but representative Todo-style CRUD API: a response record with a
-- nested optional field, a request body, a path capture, and a no-content
-- delete.

data Todo = Todo
  { todoId    :: Int
  , title     :: Text
  , completed :: Bool
  , notes     :: Maybe Text
  } deriving (Generic)

instance ToJSON Todo
instance ToSchema Todo

data NewTodo = NewTodo
  { newTitle :: Text
  , newNotes :: Maybe Text
  } deriving (Generic)

instance ToJSON NewTodo
instance ToSchema NewTodo

type TodoAPI =
       "todos" :> Get '[JSON] [Todo]
  :<|> "todos" :> ReqBody '[JSON] NewTodo :> Post '[JSON] Todo
  :<|> "todos" :> Capture "id" Int :> Get '[JSON] Todo
  :<|> "todos" :> Capture "id" Int :> ReqBody '[JSON] NewTodo :> Put '[JSON] Todo
  :<|> "todos" :> Capture "id" Int :> Delete '[JSON] NoContent

-- | The generated bare document enriched into a complete OpenAPI 3.1 contract.
spec :: O.OpenApi
spec = toOpenApi (Proxy :: Proxy TodoAPI)
  & O.info . O.title       .~ "Todo API"
  & O.info . O.version     .~ "1.0.0"
  & O.info . O.description ?~ "A small, representative Todo CRUD API."
  & O.servers              .~ ["https://api.example.com"]
  & O.applyTags            [O.Tag "todos" (Just "Operations on todo items") Nothing]
  & withOperationIds

-- | Assign a unique @operationId@ to every operation, derived from its HTTP
-- method and path (e.g. @GET \/todos\/{id}@ → @getTodosId@). Operations whose
-- method is absent on a path are left untouched.
withOperationIds :: O.OpenApi -> O.OpenApi
withOperationIds = O.paths %~ imap setForPath
  where
    setForPath path =
        (O.get    . _Just . O.operationId %~ orSet ("get"    <> key))
      . (O.post   . _Just . O.operationId %~ orSet ("create" <> key))
      . (O.put    . _Just . O.operationId %~ orSet ("update" <> key))
      . (O.delete . _Just . O.operationId %~ orSet ("delete" <> key))
      where key = camel path
    orSet v = Just . maybe v id

-- | Turn a path like @"\/todos\/{id}"@ into @"TodosId"@.
camel :: FilePath -> Text
camel = T.pack . concatMap capitalize . words . map keepAlnum
  where
    keepAlnum c   = if isAlphaNum c then c else ' '
    capitalize [] = []
    capitalize (c:cs) = toUpper c : cs

main :: IO ()
main = BL.putStrLn (encode spec)
