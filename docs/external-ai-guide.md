# 클로드(Claude Code)에서 외부 AI 사용 가이드

Claude Code 세션 안에서 외부 AI(Gemini · ChatGPT/OpenAI · Ollama)를 호출해
텍스트 생성·이미지 생성 등을 시키는 방법. 클로드가 스크립트(Python/PowerShell)를 작성·실행해
REST API를 호출하는 패턴이 기본이다.

---

## 0. 공통 원칙 — API 키 관리

1. **키를 채팅에 직접 붙여넣지 않는다.** 클로드에게는 "키를 환경변수/파일로 넣어뒀다"고만 알린다.
2. **Windows 사용자 환경변수**로 등록하는 게 표준:
   - 설정 → 시스템 → 고급 시스템 설정 → 환경 변수 → 사용자 변수에 `GEMINI_API_KEY` 등 추가
   - 또는 PowerShell: `[Environment]::SetEnvironmentVariable('GEMINI_API_KEY','<키>','User')`
3. **주의**: 클로드의 셸은 세션 시작 시점의 환경을 물려받으므로, 나중에 등록한 변수는 자동으로 안 보인다.
   클로드가 레지스트리에서 직접 읽게 하면 된다:
   ```powershell
   $env:GEMINI_API_KEY = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY','User')
   ```
4. 파일로 줄 경우(예: `.gemini_key` 한 줄) **반드시 .gitignore에 추가**.

---

## 1. Gemini (Google)

### 키 발급
- https://aistudio.google.com → **Get API key** (구글 계정만 있으면 무료 발급)

### 무료/유료 한계 (실측)
- **텍스트 모델**(gemini-2.5-flash 등): 무료 등급 사용 가능(분당/일일 요청 제한).
- **이미지 생성**(gemini-2.5-flash-image): **무료 등급 할당량 0** — 프로젝트에 **결제 연결 필수**(장당 약 $0.04).
  429 응답에 `limit: 0`이 보이면 결제 미연결 상태다.

### 호출 (REST)
```python
import json, urllib.request, os
key = os.environ["GEMINI_API_KEY"]
url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={key}"
body = {"contents": [{"parts": [{"text": "화투 12월이 왜 '비'인지 한 줄로"}]}]}
req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
print(json.loads(urllib.request.urlopen(req).read())["candidates"][0]["content"]["parts"][0]["text"])
```

이미지 생성은 모델을 `gemini-2.5-flash-image`로, `generationConfig`에
`{"responseModalities":["IMAGE"], "imageConfig":{"aspectRatio":"1:1"}}` 추가 →
응답 `candidates[].content.parts[].inlineData.data`(base64 PNG)를 디코드해 저장.
**429 처리**: 응답의 `retryDelay`만큼 대기 후 재시도(이 프로젝트 `gen_avatars.py` 참고).

---

## 2. ChatGPT (OpenAI)

### 키 발급
- https://platform.openai.com → API keys (**선불 크레딧 충전 필요** — 무료 할당 없음)
- 환경변수: `OPENAI_API_KEY`

### 텍스트 (Chat Completions)
```python
import json, urllib.request, os
req = urllib.request.Request(
    "https://api.openai.com/v1/chat/completions",
    json.dumps({"model": "gpt-4.1-mini",
                "messages": [{"role": "user", "content": "안녕"}]}).encode(),
    {"Content-Type": "application/json",
     "Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}"})
print(json.loads(urllib.request.urlopen(req).read())["choices"][0]["message"]["content"])
```

### 이미지 생성 (gpt-image-1)
```python
body = {"model": "gpt-image-1", "prompt": "Korean hwatu style phoenix", "size": "1024x1024"}
# POST https://api.openai.com/v1/images/generations (같은 Authorization 헤더)
# 응답 data[0].b64_json 을 base64 디코드해 PNG 저장
```

---

## 3. Ollama (로컬, 무료)

### 설치
- https://ollama.com → Windows 설치 → 자동으로 백그라운드 서비스 실행(`localhost:11434`)
- 모델 받기: `ollama pull llama3.2` (텍스트), `ollama pull llava` (이미지 인식/비전)
- **키 불필요, 완전 로컬·무료.** 단 **이미지 "생성"은 불가**(텍스트·비전 전용).

### 호출
```python
import json, urllib.request
req = urllib.request.Request(
    "http://localhost:11434/api/chat",
    json.dumps({"model": "llama3.2", "stream": False,
                "messages": [{"role": "user", "content": "고스톱 필승법 한 줄"}]}).encode(),
    {"Content-Type": "application/json"})
print(json.loads(urllib.request.urlopen(req).read())["message"]["content"])
```
- CLI로도 가능: `ollama run llama3.2 "질문"` — 클로드가 Bash로 바로 호출하기 가장 간단.
- 비전(이미지 입력): messages에 `"images": ["<base64>"]` 추가(llava 등 비전 모델).

---

## 4. 요약 비교

| | Gemini | ChatGPT(OpenAI) | Ollama |
|---|---|---|---|
| 키 | AI Studio(무료 발급) | platform.openai.com(충전 필요) | 불필요 |
| 텍스트 | 무료 등급 O | 유료 | 무료(로컬) |
| 이미지 생성 | **결제 연결 필수** | 유료(gpt-image-1) | ✕ |
| 이미지 인식 | O | O | O(llava 등) |
| 환경변수 | `GEMINI_API_KEY` | `OPENAI_API_KEY` | — |

## 5. 클로드에게 시키는 법 (워크플로)

1. 키를 사용자 환경변수로 등록하고 클로드에게 "GEMINI_API_KEY 등록했어"라고 알린다.
2. 클로드가 레지스트리에서 키를 읽어 스크립트를 만들고 실행한다(위 스니펫 패턴).
3. 대량 작업(이미지 20장 등)은 **백그라운드 실행 + 로그 파일**로 돌리고 완료 알림을 받는 방식이 안전하다.
4. 429/타임아웃은 스크립트 안에서 재시도(외부 API는 항상 실패를 전제로 작성).
