module Halogen.EditorComponent where

-- | The editing window - but we disallow edits although the infrastructure 
-- | is still in place.  This is because it is too expensive to transform 
-- | the ABC text to PSoM after every keystroke.

import Prelude

import Data.Either (Either(..), either)
import Data.String (null) as S
import Data.String.CodeUnits (fromCharArray, toCharArray)
import Data.Array (length, slice) as A
import Text.Parsing.StringParser (ParseError)
import Data.Abc.Parser (parse) 
import Data.Abc (AbcTune)
import Data.Maybe (Maybe(..))
import Halogen as H
import Halogen.HTML as HH
-- import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.HTML.Core (ClassName(..))
import Halogen.HTML.CSS (style)
import CSS (color)
import Color (rgb)

type Slot = H.Slot Query Message

type State =
  { text :: String
  , parseError :: Maybe ParseError
  , isEnabled :: Boolean
  }

data Action = UpdateContentAction String

data Query a =
    UpdateContent String a
  | UpdateEnabled Boolean a
  | GetText (String -> a)

data Message = TuneResult (Either ParseError AbcTune)

-- | there is no tune yet
nullTune :: Either ParseError AbcTune
nullTune =
  Left { error : "", pos : 0 }

-- component :: forall m. H.Component HH.HTML Query Unit Message m
component :: ∀ i m. H.Component Query i Message m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval
        { handleAction = handleAction
        , handleQuery = handleQuery
        , initialize = Nothing
        , finalize = Nothing
        }
    }
  where

  initialState :: i -> State
  initialState _ =
    { text : ""
    , parseError : Nothing
    , isEnabled : true
    }

  render :: State -> H.ComponentHTML Action () m
  render state =
    HH.div_
      [ HH.textarea
         [ HP.rows 14
         , HP.cols 60
         , HP.autofocus true
         , HP.value state.text
         , HP.class_ $ ClassName "abcEdit"
         , HP.enabled state.isEnabled
         , HP.readOnly true  -- make readOnly because of the expense
         -- , HP.wrap false
         -- , HE.onValueInput (Just <<< UpdateContentAction)
         ]
      , renderParseError state
      ]

handleAction ∷ ∀ m. Action → H.HalogenM State Action () Message m Unit
handleAction = case _ of
  UpdateContentAction s -> do
    -- delegate to the query
    _ <- handleQuery ((UpdateContent s) unit)
    pure unit

handleQuery :: ∀ a m. Query a -> H.HalogenM State Action () Message m (Maybe a)
handleQuery = case _ of
  UpdateContent s next -> do
    let
      tuneResult =
        if S.null s then
          nullTune
        else
          -- we need to add a terminating bar line
          parse (s <> "|\r\n")
      parseError = either Just (\_ -> Nothing) tuneResult
    _ <- H.modify (\state -> state {text = s, parseError = parseError})
    H.raise $ TuneResult tuneResult
    pure (Just next)
  UpdateEnabled isEnabled next -> do
    _ <- H.modify (\state -> state {isEnabled = isEnabled})
    pure (Just next)
  GetText reply -> do
    state <- H.get
    pure (Just (reply state.text))

renderParseError :: ∀ m. State -> H.ComponentHTML Action () m
renderParseError state =
  let
    -- the range of characters to display around each side of the error position
    textRange = 10
    txt = toCharArray state.text
  in
    case state.parseError of
      Just { error, pos } ->
        if (S.null state.text) then
          HH.div_ []
        else
          let
            -- display a prefix of 5 characters before the error (if they're there) and a suffix of 5 after
            startPhrase =
              max (pos - textRange) 0
            errorPrefix =
              A.slice startPhrase pos txt
            startSuffix =
              min (pos + 1) (A.length txt)
            endSuffix =
              min (pos + textRange + 1) (A.length txt)
            errorSuffix =
              A.slice startSuffix endSuffix txt
            errorChar =
              A.slice pos (pos + 1) txt
          in
            HH.p_
              [ HH.text $ error <> " - "
              , HH.text $ fromCharArray errorPrefix
              , HH.span
                 [ errorHighlightStyle ]
                 [ HH.text (fromCharArray errorChar) ]
              , HH.text $ fromCharArray errorSuffix
              ]
      _ ->
        HH.div_ []

errorHighlightStyle :: ∀ i r. HP.IProp (style :: String | r) i
errorHighlightStyle =
  style do
    color $ (rgb 255 0 0)
