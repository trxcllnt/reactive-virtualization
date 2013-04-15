package trxcllnt.vr
{
	import asx.fn.ifElse;
	
	import raix.interactive.IEnumerable;
	import raix.interactive.IEnumerator;
	import raix.reactive.CompositeCancelable;
	import raix.reactive.ICancelable;
	import raix.reactive.IObservable;
	import raix.reactive.IObserver;
	import raix.reactive.Observable;
	import raix.reactive.scheduling.Scheduler;

	/**
	 * @author ptaylor
	 */
	public function concatMany(enumerable:IEnumerable, selector:Function):IObservable {
		return Observable.createWithCancelable(function(observer:IObserver):ICancelable {
			
			const iterator:IEnumerator = enumerable.getEnumerator();
			const subscriptions:CompositeCancelable = new CompositeCancelable();
			
			var schedule:Function = function():void {
				subscriptions.add(Scheduler.scheduleRecursive(Scheduler.defaultScheduler, function(reschedule:Function):void {
					
					schedule = reschedule;
					
					const item:Object = iterator.current;
					const obs:IObservable = selector(item);
					
					const completed:Function = function():void {
						subscriptions.remove(subscription);
						recurse();
					};
					
					const subscription:ICancelable = obs.subscribe(observer.onNext, completed, observer.onError);
					
					subscriptions.add(subscription);
				}));
			};
			
			const recurse:Function = ifElse(
				iterator.moveNext, 
				function():void { schedule(); },
				observer.onCompleted
			);
			
			recurse();
			
			return subscriptions;
		});
	}
}