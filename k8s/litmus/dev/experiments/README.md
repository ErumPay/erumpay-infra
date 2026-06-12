# Litmus Chaos Experiments

Litmus UI에서 실험 만든 후 YAML Export해서 여기에 저장.
MongoDB PVC가 날아가도 이 파일로 Litmus UI Import 가능.

## Export 방법
1. Chaos Experiments → 실험 선택
2. Chaos Studio 열기 → 우상단 YAML 버튼
3. 복사 후 이 폴더에 `{service}-{fault}.yaml` 이름으로 저장

## Import 방법
1. New Experiment → Upload YAML 선택
2. 파일 업로드
