package trxcllnt.vr
{
	import asx.array.last;
	import asx.array.map;
	import asx.array.tail;
	import asx.fn.apply;
	import asx.fn.areEqual;
	import asx.fn.callProperty;
	import asx.fn.not;
	import asx.fn.partial;
	import asx.fn.sequence;
	
	import raix.reactive.IObservable;

	/**
	 * @author ptaylor
	 */
	public function virtualize(unit:Object,
							   updates:IObservable, /*Array<T...>*/
							   selectVisible:Function, /*(T...):IObservable<Array<Unit, R>>*/
							   reportUpdate:Function, /*(TTail..., Unit, DisplayObject):void*/
							   expandUpdate:Function):IObservable /*(TTail..., Unit, Array<Unit, R>):IObservable<Array<Unit, R>>*/ {
		
		return updates.mappend(selectVisible).map(tail).
			switchMany(sequence(
				apply(function(...args):IObservable {
					const observable:IObservable = last(args);
					return observable.map(args.slice(0, -1).concat);
				}),
				callProperty('filter', sequence(last, not(partial(areEqual, null)))),
				callProperty('peek', apply(reportUpdate)),
				callProperty('toArray')
			)).
			map(function(total:Array):Array {
				return total.length == 0 ? [] : [
					last(total)[0],
					last(total)[1],
					unit,
					map(total, callProperty('slice', -2))
				];
			}).
			switchMany(apply(expandUpdate));
	}
}