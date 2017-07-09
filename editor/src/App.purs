module App where


import Audio.SoundFont (AUDIO)
import Data.Midi.Player as MidiPlayer
import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Data.Array (length, slice)
import Data.Either (Either(..), isLeft, isRight)
import Data.List as List
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Int (fromString)
import Data.Monoid (mempty)
import Data.String (fromCharArray, toCharArray)
import View.CSS
import FileIO.FileIO (FILEIO, Filespec, loadTextFile, saveTextFile)
import Prelude (bind, const, discard, id, max, min, not, pure, show, ($), (#), (<>), (+), (-), (<<<))
import Pux (EffModel, noEffects, mapEffects, mapState)
import Pux.DOM.Events (DOMEvent, onClick, onChange, onInput, targetValue)
import Pux.DOM.HTML (HTML, child)
import Text.Smolder.HTML (button, canvas, div, h1, input, label, p, span, select, textarea)
import Text.Smolder.HTML.Attributes as At
import Text.Smolder.Markup (text, (#!), (!), (!?))
import Data.Euterpea.Music
import Data.Euterpea.Music1 (Music1, Note1(..))
import Data.Euterpea.DSL.Parser (PositionedParseError(..), parse)
import Data.Euterpea.Midi.MEvent (Performance, MEvent(..), perform1)

import Temp (perf2melody)


-- import Debug.Trace (trace, traceShow, traceShowM)

data Event
    = NoOp
    | Euterpea String
    -- | RequestFileUpload
    -- | RequestFileDownload
    -- | FileLoaded Filespec
    | PlayerEvent MidiPlayer.Event
    | Example String
    | Clear

type State = {
    polyphony :: String
  -- , fileName :: Maybe String
  , tuneResult :: Either PositionedParseError Music1
  , performance :: Performance
  , playerState :: Maybe MidiPlayer.State
}


-- | there is no tune yet
nullTune :: Either PositionedParseError Music1
nullTune =
  Left (PositionedParseError { pos : 0, error : "" })

initialState :: State
initialState = {
    polyphony : ""
  -- , fileName : Nothing
  , tuneResult : nullTune
  , performance : List.Nil
  , playerState : Nothing
  }


foldp :: Event -> State -> EffModel State Event (fileio :: FILEIO, au :: AUDIO)
foldp NoOp state =  noEffects $ state
foldp (Euterpea s) state =  onChangedEuterpea s state
foldp (Example example) state =  onChangedEuterpea example state
{-}
foldp RequestFileUpload state =
 { state: state
   , effects:
     [ do
         filespec <- loadTextFile
         pure $ Just (FileLoaded filespec)
     ]
  }
foldp (FileLoaded filespec) state =
  onChangedFile filespec state
foldp RequestFileDownload state =
   { state: state
     , effects:
       [ do
           let
             -- fileName = fromMaybe "unknown.abc" state.fileName
             fileName = getFileName state
             fsp = { name: fileName, contents : state.abc} :: Filespec
           res <- liftEff $ saveTextFile fsp
           pure $ (Just NoOp)
       ]
    }
-}
foldp Clear state =
  noEffects $ state { polyphony = ""
                    -- , fileName = Nothing
                    , tuneResult = nullTune
                    , performance = List.Nil
                    -- , playerState = Nothing
                    }
foldp (PlayerEvent e) state =
  case state.playerState of
    Just pstate ->
      MidiPlayer.foldp e pstate
        # mapEffects PlayerEvent
        # mapState \pst -> state { playerState = Just pst }
    _ ->
      noEffects state


-- | make sure everything is notified if the Euterpea Music changes for any reason
-- | we'll eventually have to add effects
onChangedEuterpea  :: forall e. String -> State ->  EffModel State Event ( e )
onChangedEuterpea polyphony state =
  let
    tuneResult =
      parse polyphony
    performance =
      case tuneResult of
        Right mus -> perform1 mus
        _ -> List.Nil

    newState =
      state { tuneResult = tuneResult, polyphony = polyphony, performance = performance }
  in
    case tuneResult of
      Right tune ->
        let
           melody = perf2melody performance
        in
          { state: newState { playerState = Just MidiPlayer.initialState}
             , effects:
               [
                do
                  pure $ Just (PlayerEvent (MidiPlayer.SetMelody melody))
              ]
          }
      Left err ->
        noEffects newState

-- | make sure everything is notified if a new file is loaded
{-}
onChangedFile :: forall e. Filespec -> State -> EffModel State Event (fileio :: FILEIO, vt :: VexScore.VEXTAB| e)
onChangedFile filespec state =
  let
    newState =
      state { fileName = Just filespec.name}
  in
    onChangedAbc filespec.contents newState
-}

-- | get the file name from the previously loaded ABC or from the ABC itseelf
{-}
getFileName :: State -> String
getFileName state =
  case state.fileName of
    Just name ->
      name
    _ ->
      case state.tuneResult of
        Right tune ->
          (fromMaybe "untitled" $ getTitle tune) <> ".abc"
        _ ->
          "untitled.abc"
-}

{-
debugPlayer :: State -> HTML Event
debugPlayer state =
  case state.playerState of
    Nothing ->
      do
        text ("no player state")
    Just pstate ->
      do
       text ("player melody size: " <> (show $ length pstate.melody))
-}

{-}
viewFileName :: State -> HTML Event
viewFileName state =
      text name
    _ ->
      mempty
-}

-- | display a snippet of text with the error highlighted
viewParseError :: State -> HTML Event
viewParseError state =
  let
    -- the range of characters to display around each side of the error position
    textRange = 10
    txt = toCharArray state.polyphony
  in
    case state.tuneResult of
      Left (PositionedParseError pe) ->
        let
          -- display a prefix of 5 characters before the error (if they're there) and a suffix of 5 after
          startPhrase =
            max (pe.pos - textRange) 0
          errorPrefix =
            slice startPhrase pe.pos txt
          startSuffix =
            min (pe.pos + 1) (length txt)
          endSuffix =
            min (pe.pos + textRange + 1) (length txt)
          errorSuffix =
            slice startSuffix endSuffix txt
          errorChar =
            slice pe.pos (pe.pos + 1) txt
        in
          p do
              text $ pe.error <> " - "
              text $ fromCharArray errorPrefix
              span ! errorHighlightStyle $ text (fromCharArray errorChar)
              text $ fromCharArray errorSuffix
      _ ->
        mempty

-- | display the intermediate Performance state
viewPerformance :: State -> HTML Event
viewPerformance state =
  do
    text $ show state.performance

-- | only display the player if we have a Melody
viewPlayer :: State -> HTML Event
viewPlayer state =
  case state.playerState of
    Just pstate ->
      child PlayerEvent MidiPlayer.view $ pstate
    _ ->
      mempty


-- | is the player playing ?
isPlaying :: State -> Boolean
isPlaying state =
  case state.playerState of
    Just ps -> ps.playing
    _ -> false


view :: State -> HTML Event
view state =
  let
    isEnabled = isRight state.tuneResult
  in
    div $ do
      h1 ! centreStyle $ text "Euterpea DSL Editor"
      -- the options and buttons on the left
      div ! leftPaneStyle $ do
        {-}
        div ! leftPanelComponentStyle $ do
          label ! labelAlignmentStyle $ do
            text "load a Euterpea file:"
          label ! inputLabelStyle ! At.className "hoverable" ! At.for "fileinput" $ text "choose"
          input ! inputStyle ! At.type' "file" ! At.id "fileinput" ! At.accept ".abc, .txt"
               #! onChange (const RequestFileUpload)
        -}
        {-}
        div ! leftPanelComponentStyle $ do
          viewFileName state
        -}
        div ! leftPanelComponentStyle  $ do
          label ! labelAlignmentStyle $ do
            -- text  "save or clear Euterpea:"
            text  "clear Euterpea:"
          -- button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const RequestFileDownload) $ text "save"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const Clear) $ text "clear"
          label ! labelAlignmentStyle $ do
              text  "simple line:"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const $ Example example1) $ text "example 1"
          label ! labelAlignmentStyle $ do
              text  "simple chords:"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const $ Example example2) $ text "example 2"
          label ! labelAlignmentStyle $ do
              text  "polska voice 1:"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const $ Example example3) $ text "example 3"
          label ! labelAlignmentStyle $ do
              text  "polska voice 2:"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const $ Example example4) $ text "example 4"
          label ! labelAlignmentStyle $ do
              text  "polska polyphony:"
          button ! (buttonStyle true) ! At.className "hoverable" #! onClick (const $ Example example5) $ text "example 5"

        div ! leftPanelComponentStyle $ do
          viewPlayer state


      -- the editable text on the right
      div ! rightPaneStyle $ do
        -- p $ text $ fromMaybe "no file chosen" state.fileName
        textarea ! taStyle ! At.cols "70" ! At.rows "15" ! At.value state.polyphony
          ! At.spellcheck "false" ! At.autocomplete "false" ! At.autofocus "true"
          #! onInput (\e -> Euterpea (targetValue e) ) $ mempty
        viewParseError state

      div! rightPaneStyle $ do
        viewPerformance state


-- | some examples
example1 :: String
example1 = "Line Note qn C 3 100, Note qn D 3 100, Note hn E 3 100, Note hn F 3 100"

example2 :: String
example2 = "Line Chord [ Note dhn A 4 100, Note dhn C 4 100, Note dhn E 3 100 ], Note qn B 4 100, Note hn A 4 100,\r\n" <>
           "    Note hn G 4 100, Chord [ Note wn E 5 100, Note wn B 4 100, Note wn G 4 100, Note wn E 4 100 ]\r\n"

example3 :: String
example3 =
  "Repeat ( \r\n" <>
  " Seq \r\n" <>
  "   Line Note en G 4 100, Note qn Bf 5 100, Note qn A 5 100, Note qn G 5 100, \r\n" <>
  "     Note sn D 5 100, Note sn E 5 100, Note sn Fs 5 100, Note sn G 5 100, Note en A 5 100, \r\n" <>
  "     Note sn A 5 100, Note sn C 6 100, Note en Bf 5 100, Note en A 5 100, \r\n" <>
  "     Note en G 5 100, Note sn Ef 6 100, Note sn D 6 100, Note en C 6 100, Note en Bf 5 100, \r\n" <>
  "     Note en A 5   100, Note en G 5 100, \r\n" <>
  "     Note sn Fs 5 100, Note sn G 5 100, Note sn A 5 100, Note sn G 5 100, Note en Fs 5 100, \r\n" <>
  "     Note en A 5 100, Note en G 5 100 \r\n" <>
  " ) \r\n"

example4 :: String
example4 =
  "Repeat ( \r\n" <>
  " Seq \r\n" <>
  "  Line Note en G 4 100, Note qn G 5 100, Note qn Fs 5 100, Note qn D 5 100, \r\n" <>
  "     Note en A 4 100, Note en D 5 100, Note en Fs 5 100, \r\n" <>
  "     Note sn Fs 5 100, Note sn A 5 100, Note en G 5 100, Note en Fs 5 100, \r\n" <>
  "     Note en D 5 100, Note sn C 6 100, Note sn Bf 5 100, Note en A 5 100, Note en G 5 100, \r\n" <>
  "     Note en Fs 5 100, Note en D 5 100, \r\n" <>
  "     Note sn D 5 100, Note sn E 5 100, Note sn Fs 5 100, Note sn D 5 100, Note en D 5 100, \r\n" <>
  "     Note en Fs 5 100, Note en D 5 100 \r\n" <>
  " ) \r\n"

example5 :: String
example5 =
  "Par \r\n" <>
    example3 <>
    example4