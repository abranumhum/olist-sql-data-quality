.PHONY: sql test
.NOTPARALLEL: sql test

sql:
	./scripts/run_pipeline.sh

test:
	uv run pytest
