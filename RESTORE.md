# 커스텀 빌드 복구

앱이 기본 버전으로 되돌아갔을 때 (아이콘이 커지거나, 드롭다운 글자가 회색으로 돌아왔을 때):

```bash
~/claude-codex-battery/restore.sh
```

빌드 → 동작 확인 → `/Applications` 교체 → 재실행까지 한 번에 합니다.

## 컴파일이 안 될 때

Xcode Command Line Tools가 깨졌거나 Swift 버전이 안 맞으면, 미리 만들어 둔 DMG로 설치합니다.
유니버설 바이너리(arm64 + x86_64)라 다른 맥에서도 씁니다.

```
app/ClaudeCodexBattery-v2.6.3-custom.dmg
```

DMG를 열어 앱을 Applications로 드래그한 뒤, 다운로드해서 옮긴 경우에만 한 번:

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeCodexBattery.app
```

DMG를 다시 만들려면 `bash app/package.sh`.

## 커스터마이징 내용

`local-customizations` 브랜치의 커밋 3개입니다. `git log --oneline main..HEAD`로 확인.

- 메뉴바 아이콘 47% 축소, 픽셀아트 대신 둥근 배터리 렌더러
- 메뉴바에는 Claude 5시간 배터리만 (주간·Fable은 드롭다운에만)
- 자동 업데이트 차단 — 업스트림 릴리스가 이 빌드를 덮어쓰지 못하게
- 드롭다운 가독성: 검정 글자 + 라이트 배경 고정 + 비활성 디밍 제거

업스트림이 새 버전을 내면:

```bash
cd ~/claude-codex-battery
git fetch origin
git rebase origin/main      # 커밋 3개를 새 버전 위에 얹음
./restore.sh
```

## 백업

`backup-upstream-build/ClaudeCodexBattery.app` — 이 커스터마이징 적용 전의 앱. git에는 올리지 않습니다.
