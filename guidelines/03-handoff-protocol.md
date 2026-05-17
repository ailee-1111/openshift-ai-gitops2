# 인수인계 프로토콜

`claude-context/handoff-notes.md`는 세션 간 "한 문단 요약"이 누적되는 로그 파일이다.

---

## 형식 (엄수)

매 세션 종료 시 **파일 하단에 아래 블록을 추가** (기존 내용 수정 금지):

~~~markdown
---

## YYYY-MM-DD Session NN — <한 줄 제목>

- 완료: <1–3개 항목>
- 진행중: <1개 또는 없음>
- 블로커: <있으면, 없으면 "없음">
- 다음 세션이 할 일: <1–2개, 구체적으로>
- 발견된 제약: <있으면 constraints.md에도 추가했음을 명시>
~~~

**총 10줄 이내**. 길어지면 증류하거나 `work-plans/`로 옮길 것.

---

## 예시

~~~markdown
## 2026-04-18 Session 03 — ArgoCD 부트스트랩

- 완료: OpenShift GitOps Operator 설치, App-of-Apps 배포
- 진행중: ServiceMesh Operator sync (CRD 생성 대기)
- 블로커: 없음
- 다음 세션이 할 일:
  1. `oc get csv -n openshift-operators`로 ServiceMesh 상태 확인
  2. 정상이면 `runbooks/100-platform-setup.md` step 3부터
- 발견된 제약: ServiceMeshControlPlane은 Operator 준비 후 30초 대기 필요 (constraints.md 반영됨)
~~~

---

## 금지

- ❌ 기존 엔트리 수정 (역사 보존)
- ❌ 10줄 초과
- ❌ "잘 됐음" 같은 모호한 문장
- ❌ state 파일의 내용 중복 (handoff는 "변화"와 "다음 할 일"에 집중)

---

## 읽기 규칙

다음 세션 시작 시:
- 최근 **3개 엔트리만** 읽으면 충분
- 그 이상 필요하면 work-plans 또는 git log 참조

---

## 이관 규칙

`handoff-notes.md`가 200줄을 넘으면:
1. 가장 오래된 절반을 `claude-context/archive/handoff-YYYY-QN.md`로 이동
2. 이관 사실을 `handoff-notes.md` 상단에 메타 주석으로 기록
