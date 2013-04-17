package trxcllnt.vr
{
	import asx.array.last;
	import asx.array.map;
	import asx.array.tail;
	import asx.fn.callProperty;
	import asx.fn.distribute;
	import asx.fn.sequence;
	
	import flash.display.DisplayObject;
	import flash.geom.Rectangle;
	
	import raix.interactive.IEnumerable;
	import raix.reactive.IObservable;

	/**
	 * @author ptaylor
	 */
	public function virtualize(unit:Object,
							   updates:IObservable, /*Array<List, Rectangle, Cache>*/
							   selectVisible:Function, /*(List, Rectangle, Cache):IObservable<Array<Unit, DisplayObject>>*/
							   reportUpdate:Function, /*(Rectangle, Cache, Unit, DisplayObject):void*/
							   expandUpdate:Function):IObservable /*(Rectangle, Cache, Unit, Array<Unit, DisplayObject>):IObservable<Array<Unit, DisplayObject>>*/
	{
		return updates.mappend(selectVisible).map(tail).
			switchMany(sequence(
				distribute(function(...args):IObservable {
					const observable:IObservable = last(args);
					return observable.map(args.slice(0, -1).concat);
				}),
				callProperty('peek', distribute(reportUpdate)),
				callProperty('toArray')
			)).
			map(function(total:Array):Array {
				return [
					last(total)[0],
					last(total)[1],
					unit,
					map(total, callProperty('slice', -2))
				];
			}).
			switchMany(distribute(expandUpdate));
	}
}