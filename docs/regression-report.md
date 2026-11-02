# Pacemaker regression report

## build: clean

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | PASS | 0 |  |
| random | 1 | PASS | 0 |  |
| random | 2 | PASS | 0 |  |
| random | 3 | PASS | 0 |  |

**all runs pass**

## build: FI_AV

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | FAIL | 25 | ERROR [MODEL] tick=2722 DUT AS/AP/VS/VP=0000 model=0001 |
| random | 1 | FAIL | 25 | ERROR [MODEL] tick=2767 DUT AS/AP/VS/VP=0000 model=0001 |
| random | 2 | FAIL | 24 | ERROR [MODEL] tick=12080 DUT AS/AP/VS/VP=0000 model=0001 |
| random | 3 | FAIL | 25 | ERROR [MODEL] tick=3546 DUT AS/AP/VS/VP=0000 model=0001 |

**fault caught**

## build: FI_PVARP

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | FAIL | 9 | ERROR [MODEL] tick=3002 DUT AS/AP/VS/VP=1000 model=0000 |
| random | 1 | FAIL | 25 | ERROR [MODEL] tick=397 DUT AS/AP/VS/VP=1000 model=0000 |
| random | 2 | FAIL | 25 | ERROR [MODEL] tick=2598 DUT AS/AP/VS/VP=1000 model=0000 |
| random | 3 | FAIL | 25 | ERROR [MODEL] tick=6620 DUT AS/AP/VS/VP=1000 model=0000 |

**fault caught**

## build: FI_AP_EARLY

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | FAIL | 25 | ERROR [MODEL] tick=2562 DUT AS/AP/VS/VP=0100 model=0000 |
| random | 1 | FAIL | 21 | ERROR [MODEL] tick=2607 DUT AS/AP/VS/VP=0100 model=0000 |
| random | 2 | FAIL | 8 | ERROR [MODEL] tick=8329 DUT AS/AP/VS/VP=0100 model=0000 |
| random | 3 | FAIL | 25 | ERROR [MODEL] tick=3386 DUT AS/AP/VS/VP=0100 model=0000 |

**fault caught**

## build: FI_NODZ

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | FAIL | 25 | ERROR [MODEL_LIF] tick=1 DUT spikes A/V=11 model=00 |
| random | 1 | FAIL | 25 | ERROR [MODEL_LIF] tick=1 DUT spikes A/V=11 model=10 |
| random | 2 | FAIL | 25 | ERROR [MODEL_LIF] tick=3 DUT spikes A/V=01 model=00 |
| random | 3 | FAIL | 25 | ERROR [MODEL_LIF] tick=4 DUT spikes A/V=01 model=00 |

**fault caught**

## build: FI_XBLANK

| test | seed | status | errors | first error |
|---|---|---|---|---|
| directed | 1 | FAIL | 3 | ERROR [MODEL] tick=857 DUT AS/AP/VS/VP=0010 model=0000 |
| random | 1 | FAIL | 3 | ERROR [MODEL] tick=24199 DUT AS/AP/VS/VP=0010 model=0000 |
| random | 2 | FAIL | 2 | ERROR [MODEL] tick=10175 DUT AS/AP/VS/VP=0010 model=0000 |
| random | 3 | FAIL | 17 | ERROR [MODEL] tick=3412 DUT AS/AP/VS/VP=0010 model=0000 |

**fault caught**
