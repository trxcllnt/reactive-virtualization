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
							   selectVisible:Function, /*(List, Rectangle, Cache):<Enumerable>*/
							   expandChild:Function, /*(Unit):IObservable<Array<Unit, DisplayObject>>*/
							   reportUpdate:Function, /*(Rectangle, Cache, Unit, DisplayObject):void*/
							   expandUpdate:Function):IObservable /*(Rectangle, Cache, Unit, Array<DisplayObject>):IObservable<Array<Unit, DisplayObject>>*/
	{
		return updates.mappend(selectVisible).map(tail).
			switchMany(sequence(
				distribute(function(viewport:Rectangle, cache:Virtualizer, enumerable:IEnumerable):IObservable {
					return concatMany(enumerable, expandChild).
						map(distribute(function(unit:Object, child:DisplayObject):Array {
							return [viewport, cache, unit, child];
						}));
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