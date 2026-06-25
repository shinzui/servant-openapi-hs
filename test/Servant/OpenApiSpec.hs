{-# LANGUAGE CPP                #-}
{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE QuasiQuotes        #-}
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE PackageImports     #-}
#if MIN_VERSION_servant(0,18,1)
{-# LANGUAGE TypeFamilies       #-}
#endif
module Servant.OpenApiSpec where

import           Control.Lens
import           Data.Aeson                    (ToJSON (toJSON), Value, eitherDecode, encode, genericToJSON)
import           Data.Aeson.Lens               (key, members, _String)
import           Data.Aeson.QQ.Simple
import qualified Data.Aeson.Types              as JSON
import           Data.Char                     (toLower)
import           Data.Int                      (Int64)
import           Data.OpenApi
import           Data.Proxy
import           Data.Text                     (Text)
import           Data.Time
import           GHC.Generics
import           Servant.API
import           Servant.OpenApi
import           Servant.Test.ComprehensiveAPI (comprehensiveAPI)
import           Test.Hspec                    hiding (example)
import           Test.QuickCheck               (Arbitrary (..))

checkAPI :: HasCallStack => HasOpenApi api => Proxy api -> Value -> IO ()
checkAPI proxy = checkOpenApi (toOpenApi proxy)

checkOpenApi :: HasCallStack => OpenApi -> Value -> IO ()
checkOpenApi swag js = encode (toJSON swag) `shouldBe` (encode js)

spec :: Spec
spec = do
  describe "HasOpenApi" $ do
    it "Todo API" $ checkAPI (Proxy :: Proxy TodoAPI) todoAPI
    it "Hackage API (with tags)" $ checkOpenApi hackageOpenApiWithTags hackageAPI
    it "GetPost API (test subOperations)" $ checkOpenApi getPostOpenApi getPostAPI
    it "Comprehensive API" $ do
      -- Exercising every servant combinator must not merely compile: it must
      -- still emit a valid 3.1 document with a non-empty set of paths.
      let doc = toJSON (toOpenApi comprehensiveAPI)
      doc ^? key "openapi" . _String `shouldBe` Just "3.1.0"
      lengthOf (key "paths" . members) doc `shouldSatisfy` (> 0)
#if MIN_VERSION_servant(0,18,1)
    it "UVerb API" $ checkOpenApi uverbOpenApi uverbAPI
#endif

  -- Layer 1: every generated document round-trips through openapi-hs's
  -- 'FromJSON OpenApi', which rejects any version outside 3.1.0 .. 3.1.1.
  -- A successful @eitherDecode (encode spec) == Right spec@ therefore proves
  -- the emitted JSON is a structurally valid OpenAPI 3.1 document.
  describe "round-trips through openapi-hs (valid OpenAPI 3.1)" $ do
    it "Todo API" $ roundTrips (toOpenApi (Proxy :: Proxy TodoAPI))
    it "Hackage API" $ roundTrips hackageOpenApiWithTags
    it "GetPost API" $ roundTrips getPostOpenApi
    it "Comprehensive API" $ roundTrips (toOpenApi comprehensiveAPI)
#if MIN_VERSION_servant(0,18,1)
    it "UVerb API" $ roundTrips uverbOpenApi
#endif

  -- Layer 2: generated random values of each JSON body type are validated
  -- against the *generated* schema, proving the schemas describe the data.
  describe "validateEveryToJSON (schemas describe their data)" $
    validateEveryToJSON (Proxy :: Proxy ValidationAPI)

  -- The 3.1-specific rendering this fork exists to provide, asserted directly
  -- on the generated JSON so a regression to 3.0 output fails loudly.
  describe "OpenAPI 3.1 rendering" $ do
    it "declares openapi version 3.1.0" $
      toJSON (toOpenApi (Proxy :: Proxy TodoAPI)) ^? key "openapi" . _String
        `shouldBe` Just "3.1.0"

    it "expresses nullability as a type array, not a `nullable` keyword" $ do
      let doc      = toJSON (toOpenApi (Proxy :: Proxy NullableAPI))
          nickName = doc ^? key "components" . key "schemas" . key "Nickname"
      -- 3.1: nullability lives in the type array @["string","null"]@ ...
      (nickName >>= (^? key "type")) `shouldBe` Just (toJSON ["string", "null" :: Text])
      -- ... and the 3.0-only @nullable@ keyword must not be emitted anywhere.
      (nickName >>= (^? key "nullable")) `shouldBe` Nothing

-- | Layer 1 assertion: a document survives a parse by openapi-hs's
-- @FromJSON OpenApi@ — which rejects any version outside 3.1.0 .. 3.1.1 — and
-- re-serializes to a semantically identical JSON document, proving it is a
-- structurally valid, correctly-versioned OpenAPI 3.1 document.
--
-- The comparison is at the aeson 'Value' level rather than on @OpenApi@ values
-- or raw bytes, for two reasons:
--
--   * @Eq@ for @InsOrdHashSet@ (used by @tags@ / @operationTags@) is sensitive
--     to an internal index counter that a JSON round-trip does not preserve, so
--     @decoded == Right s@ fails for semantically identical documents.
--   * aeson decodes JSON objects into an order-insensitive @KeyMap@, so the
--     re-encoded bytes differ in key order from the original even when the
--     documents are identical.
--
-- Comparing 'Value's sidesteps both: object key order is irrelevant to 'Value'
-- equality while array order (e.g. @required@, @enum@) still is.
roundTrips :: HasCallStack => OpenApi -> Expectation
roundTrips s = case eitherDecode (encode s) :: Either String OpenApi of
  Left err -> expectationFailure ("did not decode as OpenAPI 3.1: " ++ err)
  Right d  -> toJSON d `shouldBe` toJSON s

main :: IO ()
main = hspec spec

-- =======================================================================
-- Validation API (Layer 2)
-- =======================================================================

data Health = Health
  { status :: String
  , uptime :: Int
  } deriving (Eq, Show, Generic)

instance ToJSON Health
instance ToSchema Health
instance Arbitrary Health where
  arbitrary = Health <$> arbitrary <*> arbitrary

type ValidationAPI =
       "health" :> Get '[JSON] Health
  :<|> "health" :> ReqBody '[JSON] Health :> Post '[JSON] Health

-- =======================================================================
-- Nullable API (OpenAPI 3.1 type-array nullability)
-- =======================================================================

-- | A type whose schema is explicitly nullable. Under OpenAPI 3.1 this must
-- render as @"type": ["string","null"]@ rather than the 3.0 @nullable: true@,
-- so it pins the headline difference between this fork and its 3.0 upstream.
newtype Nickname = Nickname (Maybe Text) deriving (Generic)

instance ToJSON Nickname

instance ToSchema Nickname where
  declareNamedSchema _ = pure $
    NamedSchema (Just "Nickname") $
      mempty & type_ ?~ OpenApiTypeArray [OpenApiString, OpenApiNull]

type NullableAPI = "nick" :> Get '[JSON] Nickname

-- =======================================================================
-- Todo API
-- =======================================================================

data Todo = Todo
  { created :: UTCTime
  , title   :: String
  , summary :: Maybe String
  } deriving (Generic)

instance ToJSON Todo
instance ToSchema Todo

newtype TodoId = TodoId String deriving (Generic)
instance ToParamSchema TodoId

type TodoAPI = "todo" :> Capture "id" TodoId :> Get '[JSON] Todo

todoAPI :: Value
todoAPI = [aesonQQ|
{
  "openapi": "3.1.0",
  "info": {
    "version": "",
    "title": ""
  },
  "components": {
    "schemas": {
      "Todo": {
        "required": [
          "created",
          "title"
        ],
        "type": "object",
        "properties": {
          "summary": {
            "type": "string"
          },
          "created": {
            "$ref": "#/components/schemas/UTCTime"
          },
          "title": {
            "type": "string"
          }
        }
      },
      "UTCTime": {
        "example": "2016-07-22T00:00:00Z",
        "format": "yyyy-mm-ddThh:MM:ssZ",
        "type": "string"
      }
    }
  },
  "paths": {
    "/todo/{id}": {
      "get": {
        "responses": {
          "404": {
            "description": "`id` not found"
          },
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "$ref": "#/components/schemas/Todo"
                }
              }
            },
            "description": ""
          }
        },
        "parameters": [
          {
            "required": true,
            "schema": {
              "type": "string"
            },
            "in": "path",
            "name": "id"
          }
        ]
      }
    }
  }
}
|]

-- =======================================================================
-- Hackage API
-- =======================================================================

type HackageAPI
    = HackageUserAPI
 :<|> HackagePackagesAPI

type HackageUserAPI =
      "users" :> Get '[JSON] [UserSummary]
 :<|> "user"  :> Capture "username" Username :> Get '[JSON] UserDetailed

type HackagePackagesAPI
    = "packages" :> Get '[JSON] [Package]

type Username = Text

data UserSummary = UserSummary
  { summaryUsername :: Username
  , summaryUserid   :: Int64  -- Word64 would make sense too
  } deriving (Eq, Show, Generic)

lowerCutPrefix :: String -> String -> String
lowerCutPrefix s = map toLower . drop (length s)

instance ToJSON UserSummary where
  toJSON = genericToJSON JSON.defaultOptions { JSON.fieldLabelModifier = lowerCutPrefix "summary" }

instance ToSchema UserSummary where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions { fieldLabelModifier = lowerCutPrefix "summary" } proxy
    & mapped.schema.example ?~ toJSON UserSummary
         { summaryUsername = "JohnDoe"
         , summaryUserid   = 123 }

type Group = Text

data UserDetailed = UserDetailed
  { username :: Username
  , userid   :: Int64
  , groups   :: [Group]
  } deriving (Eq, Show, Generic)
instance ToSchema UserDetailed

newtype Package = Package { packageName :: Text }
  deriving (Eq, Show, Generic)
instance ToSchema Package

hackageOpenApiWithTags :: OpenApi
hackageOpenApiWithTags = toOpenApi (Proxy :: Proxy HackageAPI)
  & servers .~ ["https://hackage.haskell.org"]
  & applyTagsFor usersOps    ["users"    & description ?~ "Operations about user"]
  & applyTagsFor packagesOps ["packages" & description ?~ "Query packages"]
  where
    usersOps, packagesOps :: Traversal' OpenApi Operation
    usersOps    = subOperations (Proxy :: Proxy HackageUserAPI)     (Proxy :: Proxy HackageAPI)
    packagesOps = subOperations (Proxy :: Proxy HackagePackagesAPI) (Proxy :: Proxy HackageAPI)

hackageAPI :: Value
hackageAPI = [aesonQQ|
{
  "openapi": "3.1.0",
  "servers": [
    {
      "url": "https://hackage.haskell.org"
    }
  ],
  "components": {
    "schemas": {
      "UserDetailed": {
        "required": [
          "username",
          "userid",
          "groups"
        ],
        "type": "object",
        "properties": {
          "groups": {
            "items": {
              "type": "string"
            },
            "type": "array"
          },
          "username": {
            "type": "string"
          },
          "userid": {
            "maximum": 9223372036854775807,
            "format": "int64",
            "minimum": -9223372036854775808,
            "type": "integer"
          }
        }
      },
      "Package": {
        "required": [
          "packageName"
        ],
        "type": "object",
        "properties": {
          "packageName": {
            "type": "string"
          }
        }
      },
      "UserSummary": {
        "example": {
          "username": "JohnDoe",
          "userid": 123
        },
        "required": [
          "username",
          "userid"
        ],
        "type": "object",
        "properties": {
          "username": {
            "type": "string"
          },
          "userid": {
            "maximum": 9223372036854775807,
            "format": "int64",
            "minimum": -9223372036854775808,
            "type": "integer"
          }
        }
      }
    }
  },
  "info": {
    "version": "",
    "title": ""
  },
  "paths": {
    "/users": {
      "get": {
        "responses": {
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "items": {
                    "$ref": "#/components/schemas/UserSummary"
                  },
                  "type": "array"
                }
              }
            },
            "description": ""
          }
        },
        "tags": [
          "users"
        ]
      }
    },
    "/packages": {
      "get": {
        "responses": {
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "items": {
                    "$ref": "#/components/schemas/Package"
                  },
                  "type": "array"
                }
              }
            },
            "description": ""
          }
        },
        "tags": [
          "packages"
        ]
      }
    },
    "/user/{username}": {
      "get": {
        "responses": {
          "404": {
            "description": "`username` not found"
          },
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "$ref": "#/components/schemas/UserDetailed"
                }
              }
            },
            "description": ""
          }
        },
        "parameters": [
          {
            "required": true,
            "schema": {
              "type": "string"
            },
            "in": "path",
            "name": "username"
          }
        ],
        "tags": [
          "users"
        ]
      }
    }
  },
  "tags": [
    {
      "name": "users",
      "description": "Operations about user"
    },
    {
      "name": "packages",
      "description": "Query packages"
    }
  ]
}
|]


-- =======================================================================
-- Get/Post API (test for subOperations)
-- =======================================================================

type GetPostAPI = Get '[JSON] String :<|> Post '[JSON] String

getPostOpenApi :: OpenApi
getPostOpenApi = toOpenApi (Proxy :: Proxy GetPostAPI)
  & applyTagsFor getOps ["get" & description ?~ "GET operations"]
  where
    getOps :: Traversal' OpenApi Operation
    getOps = subOperations (Proxy :: Proxy (Get '[JSON] String)) (Proxy :: Proxy GetPostAPI)

getPostAPI :: Value
getPostAPI = [aesonQQ|
{
  "components": {},
  "openapi": "3.1.0",
  "info": {
    "version": "",
    "title": ""
  },
  "paths": {
    "/": {
      "post": {
        "responses": {
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "type": "string"
                }
              }
            },
            "description": ""
          }
        }
      },
      "get": {
        "responses": {
          "200": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "type": "string"
                }
              }
            },
            "description": ""
          }
        },
        "tags": [
          "get"
        ]
      }
    }
  },
  "tags": [
    {
      "name": "get",
      "description": "GET operations"
    }
  ]
}
|]

-- =======================================================================
-- UVerb API
-- =======================================================================

#if MIN_VERSION_servant(0,18,1)

data FisxUser = FisxUser {name :: String}
  deriving (Eq, Show, Generic)

instance ToSchema FisxUser

instance HasStatus FisxUser where
  type StatusOf FisxUser = 203

data ArianUser = ArianUser
  deriving (Eq, Show, Generic)

instance ToSchema ArianUser

type UVerbAPI = "fisx" :> UVerb 'GET '[JSON] '[FisxUser, WithStatus 303 String]
           :<|> "arian" :> UVerb 'POST '[JSON] '[WithStatus 201 ArianUser]

uverbOpenApi :: OpenApi
uverbOpenApi = toOpenApi (Proxy :: Proxy UVerbAPI)

uverbAPI :: Value
uverbAPI = [aesonQQ|
{
  "openapi": "3.1.0",
  "info": {
    "version": "",
    "title": ""
  },
  "components": {
    "schemas": {
      "ArianUser": {
        "type": "string",
        "enum": [
          "ArianUser"
        ]
      },
      "FisxUser": {
        "required": [
          "name"
        ],
        "type": "object",
        "properties": {
          "name": {
            "type": "string"
          }
        }
      }
    }
  },
  "paths": {
    "/arian": {
      "post": {
        "responses": {
          "201": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "$ref": "#/components/schemas/ArianUser"
                }
              }
            },
            "description": ""
          }
        }
      }
    },
    "/fisx": {
      "get": {
        "responses": {
          "303": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "type": "string"
                }
              }
            },
            "description": ""
          },
          "203": {
            "content": {
              "application/json;charset=utf-8": {
                "schema": {
                  "$ref": "#/components/schemas/FisxUser"
                }
              }
            },
            "description": ""
          }
        }
      }
    }
  }
}
|]

#endif
