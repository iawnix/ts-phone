source /home/iaw/soft/flutter/activate.sh
source /home/iaw/soft/android_sdk/activate.sh
source /home/iaw/soft/jdk_21/activate.sh

export FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"
export DART_BIN="$DART_HOME/bin/dart"
export ANDROID_SDK="$ANDROID_SDK_ROOT"
export JAVA_HOME_PATH="$JAVA_HOME"
export GRADLE_USER_HOME=/home/iaw/.gradle
export PUB_CACHE=/home/iaw/project/ts-phone/.pub-cache
export TS_PHONE_SIGNING_DIR=/home/iaw/.config/ts-phone/android-signing

./tool/iterate.sh candidate
