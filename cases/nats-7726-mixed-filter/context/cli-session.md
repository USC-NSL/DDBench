# CLI Session

Obtained by running `./nats-server -js -p 4222 -sd /tmp/js` from the buggy build and then the following `nats` CLI commands against it (`NATS_URL=nats://127.0.0.1:4222`):

```
nats stream add ORDERS --subjects "events.>" --storage file --retention limits --defaults
nats consumer add ORDERS worker --filter "events.*.datastore.batch.access.modified" --filter "events.*.processor.complete.batch.inserted" --filter "events.main.datastore.result.created" --ack explicit --pull --deliver all --defaults
nats pub -q events.main.datastore.record.created msg
nats pub -q events.main.datastore.group.created msg
nats pub -q events.main.datastore.batch.created msg
nats pub -q events.main.datastore.items.created msg   # 4 times
nats pub events.main.datastore.result.created hello
nats stream subjects ORDERS
nats consumer info ORDERS worker
nats consumer next ORDERS worker --count 1 --timeout 3s
```

## Output

```
12:15:36 Published 5 bytes to "events.main.datastore.result.created"
╭──────────────────────────────────────────────╮
│          5 Subjects in stream ORDERS         │
├──────────────────────────────────────┬───────┤
│ Subject                              │ Count │
├──────────────────────────────────────┼───────┤
│ events.main.datastore.group.created  │ 1     │
│ events.main.datastore.record.created │ 1     │
│ events.main.datastore.result.created │ 1     │
│ events.main.datastore.batch.created  │ 1     │
│ events.main.datastore.items.created  │ 4     │
╰──────────────────────────────────────┴───────╯

Information for Consumer ORDERS > worker created 2026-10-14 12:15:36

Configuration:

                    Name: worker
               Pull Mode: true
         Filter Subjects: events.*.datastore.batch.access.modified, events.*.processor.complete.batch.inserted, events.main.datastore.result.created
          Deliver Policy: All
              Ack Policy: Explicit
                Ack Wait: 30.00s
           Replay Policy: Instant
         Max Ack Pending: 1,000
       Max Waiting Pulls: 512

State:

            Host Version: 2.14.0-dev
      Required API Level: 0 hosted at level 2
  Last Delivered Message: Consumer sequence: 0 Stream sequence: 0
    Acknowledgment Floor: Consumer sequence: 0 Stream sequence: 0
        Outstanding Acks: 0 out of maximum 1,000
    Redelivered Messages: 0
    Unprocessed Messages: 1
           Waiting Pulls: 0 of maximum 512

nats: error: no message received: nats: timeout
```
