import os

import jpype
import jpype.imports  # This module is imported for its side effects


def ensure_jvm():
    # JVM initialization logic belongs here
    if not jpype.isJVMStarted():
        jpype.startJVM(
            "--enable-native-access=ALL-UNNAMED",  # Needed to suppress deprecation warning
            classpath=[os.environ.get("RT_AUTOMATON_JAR", "jars/automaton.jar")],
        )


ensure_jvm()


# Import all java constructs here and access them in the rest of the project through this module
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
