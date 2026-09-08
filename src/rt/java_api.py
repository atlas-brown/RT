import os

import jpype
import jpype.imports 

def ensure_jvm():
    if not jpype.isJVMStarted():
        jpype.startJVM(
            "--enable-native-access=ALL-UNNAMED",  # Needed to suppress deprecation warning
            classpath=[os.environ.get("RT_AUTOMATON_JAR", "jars/automaton.jar")],
        )
        
ensure_jvm()

# isort: off
from dk.brics.automaton import (  # pyright: ignore[reportMissingModuleSource]
    Automaton,
    BasicAutomata,
    BasicOperations,
    RegExp,
    SpecialOperations,
    State as AutomatonState,
    Transition as AutomatonTransition,
)  # isort: on
