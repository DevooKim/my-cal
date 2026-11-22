# MyCal

Itsycal 스타일의 macOS 메뉴바 달력 앱. 일정이 다가오거나 진행 중일 때 메뉴바 아이콘 대신 일정 제목과 남은 시간을 보여준다.

```
● 주간 팀 회의 · 17분 남음
● 디자인 리뷰 · 25분 후
```

## 빌드

Xcode 없이 Command Line Tools만으로 빌드한다.

```sh
./scripts/build-app.sh   # build/MyCal.app 생성
open build/MyCal.app
./scripts/make-dmg.sh    # build/MyCal-<버전>.dmg 생성 (인자로 출력 폴더 지정 가능)
swift test               # 메뉴바 표시 로직 테스트
```

Command Line Tools에서 `plugin for module 'TestingMacros' not found` 오류가 나면, 설치된 Swift Testing 플러그인을 명시해 실행한다.

```sh
swift test -Xswiftc -load-plugin-library \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
```

ad-hoc 서명이라 다시 빌드하면 macOS가 다른 앱으로 인식한다. 캘린더 권한을 다시 허용해야 하면
`tccutil reset Calendar app.mycal.menubar` 후 앱을 다시 실행한다.

기존 버전에서 옮겨오는 경우 번들 ID가 달라 캘린더 권한과 앱 설정을 다시 지정해야 한다.

## 설정

- 메뉴바: 제목 표시 여부, 회의실 위치 표시 여부, 표시 시작 시점(진행 중일 때만 ~ 12시간 전), 제목 최대 글자 수
- 달력: 한 주의 시작 요일, 목록에 표시할 날짜 수
- 캘린더: 캘린더별로 달력·목록 표시 여부와 메뉴바 제목 사용 여부
- 일반: 캘린더 버튼으로 열 앱(macOS 캘린더, Google Calendar 웹, 직접 고른 앱), 로그인 시 자동 실행
