# Code Investigation

## What was searched
The symptom describes a `fatal error: concurrent map iteration and map write` when many clients concurrently create, update and delete durable consumers on a WorkQueue stream. Read the consumer create/update path in `server/consumer.go` that runs for these API requests, and the WorkQueue filter-uniqueness check it calls in `server/stream.go`.

## What was found
```
$ cat -n server/consumer.go | sed -n '1017,1090p'
  1017		// Hold mset lock here.
  1018		mset.mu.Lock()
  1019		if mset.client == nil || mset.store == nil || mset.consumers == nil {
  1020			mset.mu.Unlock()
  1021			return nil, NewJSStreamInvalidError()
  1022		}
  1023	
  1024		// If this one is durable and already exists, we let that be ok as long as only updating what should be allowed.
  1025		var cName string
  1026		if isDurableConsumer(config) {
  1027			cName = config.Durable
  1028		} else if config.Name != _EMPTY_ {
  1029			cName = config.Name
  1030		}
  1031		if cName != _EMPTY_ {
  1032			if eo, ok := mset.consumers[cName]; ok {
  1033				mset.mu.Unlock()
  1034				if action == ActionCreate {
  1035					ocfg := eo.config()
  1036					copyConsumerMetadata(config, &ocfg)
  1037					if !reflect.DeepEqual(config, &ocfg) {
  1038						return nil, NewJSConsumerAlreadyExistsError()
  1039					}
  1040				}
  1041				// Check for overlapping subjects if we are a workqueue
  1042				if cfg.Retention == WorkQueuePolicy {
  1043					subjects := gatherSubjectFilters(config.FilterSubject, config.FilterSubjects)
  1044					if !mset.partitionUnique(cName, subjects) {
  1045						return nil, NewJSConsumerWQConsumerNotUniqueError()
  1046					}
  1047				}
  1048				err := eo.updateConfig(config)
  1049				if err == nil {
  1050					return eo, nil
  1051				}
  1052				return nil, NewJSConsumerCreateError(err, Unless(err))
  1053			}
  1054		}
  1055		if action == ActionUpdate {
  1056			mset.mu.Unlock()
  1057			return nil, NewJSConsumerDoesNotExistError()
  1058		}
  1059	
  1060		// Check for any limits, if the config for the consumer sets a limit we check against that
  1061		// but if not we use the value from account limits, if account limits is more restrictive
  1062		// than stream config we prefer the account limits to handle cases where account limits are
  1063		// updated during the lifecycle of the stream
  1064		maxc := cfg.MaxConsumers
  1065		if maxc <= 0 || (selectedLimits.MaxConsumers > 0 && selectedLimits.MaxConsumers < maxc) {
  1066			maxc = selectedLimits.MaxConsumers
  1067		}
  1068		if maxc > 0 && mset.numPublicConsumers() >= maxc {
  1069			mset.mu.Unlock()
  1070			return nil, NewJSMaximumConsumersLimitError()
  1071		}
  1072	
  1073		// Check on stream type conflicts with WorkQueues.
  1074		if cfg.Retention == WorkQueuePolicy && !config.Direct {
  1075			// Force explicit acks here.
  1076			if config.AckPolicy != AckExplicit {
  1077				mset.mu.Unlock()
  1078				return nil, NewJSConsumerWQRequiresExplicitAckError()
  1079			}
  1080	
  1081			if len(mset.consumers) > 0 {
  1082				subjects := gatherSubjectFilters(config.FilterSubject, config.FilterSubjects)
  1083				if len(subjects) == 0 {
  1084					mset.mu.Unlock()
  1085					return nil, NewJSConsumerWQMultipleUnfilteredError()
  1086				} else if !mset.partitionUnique(cName, subjects) {
  1087					// Prior to v2.9.7, on a stream with WorkQueue policy, the servers
  1088					// were not catching the error of having multiple consumers with
  1089					// overlapping filter subjects depending on the scope, for instance
  1090					// creating "foo.*.bar" and then "foo.>" was not detected, while
```

```
$ cat -n server/stream.go | sed -n '7474,7494p'
  7474	// Determines if the new proposed partition is unique amongst all consumers.
  7475	// Lock should be held.
  7476	func (mset *stream) partitionUnique(name string, partitions []string) bool {
  7477		for _, partition := range partitions {
  7478			for n, o := range mset.consumers {
  7479				// Skip the consumer being checked.
  7480				if n == name {
  7481					continue
  7482				}
  7483				if o.subjf == nil {
  7484					return false
  7485				}
  7486				for _, filter := range o.subjf {
  7487					if SubjectsCollide(partition, filter.subject) {
  7488						return false
  7489					}
  7490				}
  7491			}
  7492		}
  7493		return true
  7494	}
```

## Developer hypothesis
The consumer create/update path and the stream's consumer bookkeeping both use `mset.consumers` under `mset.mu`. Worth checking which locks are held at each point where the create/update path reads that map.
