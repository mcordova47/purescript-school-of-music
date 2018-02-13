module Container where

import Prelude

import Audio.SoundFont (AUDIO, Instrument, loadRemoteSoundFonts)
import Audio.SoundFont.Melody.Class (class Playable, toMelody)
import Control.Monad.Aff (Aff)
import Data.Either (Either(..))
import Data.Either.Nested (Either5)
import Data.Euterpea.DSL.Parser (PSoM, PositionedParseError(..))
import Audio.Euterpea.Playable (PlayablePSoM(..))
import Data.Functor.Coproduct.Nested (Coproduct5)
import Data.List (List(..))
import Data.Maybe (Maybe(..))
import Data.Array (cons, length)
import Data.Foldable (foldl)
import Data.MediaType (MediaType(..))
import Data.Midi.Instrument (InstrumentName(..), gleitzmanNames, read)
import FileInputComponent as FIC
import Halogen as H
import Halogen.Component.ChildPath as CP
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import JS.FileIO (FILEIO, Filespec)
import MultipleSelect.Dom (SDOM)
import MultipleSelectComponent as MSC
import PlayerComponent as PC
import EditorComponent as ED
import SimpleButtonComponent as Button

import Network.HTTP.Affjax (AJAX)

type AppEffects eff = (ajax :: AJAX, au :: AUDIO, fileio :: FILEIO, sdom :: SDOM | eff)

type State =
  { instruments :: Array Instrument
  , tuneResult :: Either PositionedParseError PSoM
  }

data Query a =
    HandleFICButton FIC.Message a
  | HandleNewTuneText ED.Message a
  | HandleMultiSelectCommit MSC.Message a

fileInputCtx :: FIC.FileInputContext
fileInputCtx =
  { componentId : "psominput"
  , isBinary : false
  , prompt : "load a PSoM file:"
  , accept : MediaType ".psom"
  }

initialMultipleSelectState :: MSC.State
initialMultipleSelectState =
  { instruction : "add an instrument"
  , available : gleitzmanNames
  , selected : Nil
  }

-- | there is no tune yet
nullTune :: Either PositionedParseError PSoM
nullTune =
  Left (PositionedParseError { pos : 0, error : "" })

parseError :: Either PositionedParseError PSoM -> String
parseError tuneResult =
  case tuneResult of
    Right _ -> "no errors"
    Left (PositionedParseError ppe) -> "parse error: " <> ppe.error

type ChildQuery = Coproduct5 ED.Query FIC.Query MSC.Query Button.Query PC.Query

-- slots and slot numbers
type FileInputSlot = Unit
type MultipleSelectSlot = Unit
type PlayerSlot = Unit
type ReplaceInstrumentsSlot = Unit
type EditorSlot = Unit

type ChildSlot = Either5 Unit Unit Unit Unit Unit

editorSlotNo :: CP.ChildPath ED.Query ChildQuery EditorSlot ChildSlot
editorSlotNo = CP.cp1

psomFileSlotNo :: CP.ChildPath FIC.Query ChildQuery FileInputSlot ChildSlot
psomFileSlotNo = CP.cp2

instrumentSelectSlotNo :: CP.ChildPath MSC.Query ChildQuery MultipleSelectSlot ChildSlot
instrumentSelectSlotNo = CP.cp3

cpRISlotNo :: CP.ChildPath Button.Query ChildQuery ReplaceInstrumentsSlot ChildSlot
cpRISlotNo = CP.cp4

playerSlotNo :: CP.ChildPath PC.Query ChildQuery PlayerSlot ChildSlot
playerSlotNo = CP.cp5


component ::  ∀ eff. H.Component HH.HTML Query Unit Void (Aff (AppEffects eff))
-- component ::  ∀ eff p. H.Component HH.HTML Query Unit Void (Aff (au :: AUDIO, fileio :: FILEIO, sdom :: SDOM | eff))
component =
  H.parentComponent
    { initialState: const initialState
    , render
    , eval
    , receiver: const Nothing
    }
  where

  initialState :: State
  initialState = { instruments: []
                 , tuneResult: nullTune
                 }

  render :: State -> H.ParentHTML Query ChildQuery ChildSlot (Aff (AppEffects eff))
  render state = HH.div_
    [ HH.div
        [ HP.class_ (H.ClassName "box")]
        [ HH.h1_ [ HH.text "Text Area Component" ]
        , HH.slot' editorSlotNo unit (ED.component "foo") unit (HE.input HandleNewTuneText)
        ]
    , HH.div
        [ HP.class_ (H.ClassName "box")]
        [ HH.h1_ [ HH.text "File Input Component" ]
        , HH.slot' psomFileSlotNo unit (FIC.component fileInputCtx) unit (HE.input HandleFICButton)
        ]
    , HH.div
        [ HP.class_ (H.ClassName "box")]
        [ HH.h1_ [ HH.text "Multiple Select Component" ]
        , HH.slot' instrumentSelectSlotNo unit (MSC.component initialMultipleSelectState) unit (HE.input HandleMultiSelectCommit)
        ]
    , renderPlayer state
    , HH.p_
        [ HH.text "Last observed states:"]
    , HH.ul_
        [ HH.li_ [ HH.text ("instruments loaded: " <> show (length state.instruments)) ]
        , HH.li_ [ HH.text ("tune errors: " <> (parseError state.tuneResult)) ]
        ]
    ]

  renderPlayer ::  ∀ eff. State -> H.ParentHTML Query ChildQuery ChildSlot (Aff (au :: AUDIO | eff))
  renderPlayer state =
    case state.tuneResult of
      Right psom ->
        HH.div
          [ HP.class_ (H.ClassName "box")]
          [ HH.slot' playerSlotNo unit (PC.component (PlayablePSoM psom) state.instruments) unit absurd  ]
      Left err ->
        HH.div_
          [ HH.text "no tune to play" ]
          

  eval :: Query ~> H.ParentDSL State Query ChildQuery ChildSlot Void (Aff (AppEffects eff))
  eval (HandleFICButton (FIC.FileLoaded filespec) next) = do
    _ <- H.query' editorSlotNo unit $ H.action (ED.UpdateContent filespec.contents)
    pure next
  eval (HandleNewTuneText (ED.TuneResult r) next) = do
    H.modify (\st -> st { tuneResult = r} )
    pure next
  eval (HandleMultiSelectCommit (MSC.CommittedSelections pendingInstrumentNames) next) = do
    -- state <- H.get
    let
      f acc s =
        case read s of
          Just inst -> cons inst acc
          _ -> acc
      instrumentNames :: Array InstrumentName
      instrumentNames = foldl f [] pendingInstrumentNames
    instruments <- H.liftAff $ loadRemoteSoundFonts instrumentNames
    H.modify (\st -> st { instruments = instruments})
    pure next
