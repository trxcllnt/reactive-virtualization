package trxcllnt.vr
{
	import flash.utils.Dictionary;
	
	/**
	 * A sparse array implementation.
	 */
	public final class Virtualizer
	{
		private var vector:SparseArray = new SparseArray();
		private var indexCache:Array = [];
		private var itemCache:Dictionary = new Dictionary(false);
		
		public function get size():int
		{
			return vector.length == 0 ? 0 : vector.end(vector.length - 1);
		}
		
		public function get length():int
		{
			return indexCache.length;
		}
		
		public function get items():Array
		{
			return indexCache.concat();
		}
		
		public function get gap():Number {
			return vector.gap;
		}
		
		public function set gap(value:Number):void {
			vector.gap = value;
		}
		
		public function clear():void
		{
			vector = new SparseArray();
			indexCache = []
			itemCache = new Dictionary(false);
		}
		
		public function add(item:*, size:int):*
		{
			return addAt(item, length, size);
		}
		
		public function addAt(item:*, index:int, size:int):*
		{
			if(item in itemCache)
				return item;
			
			if(size <= 0)
				size = 1;
			
			indexCache.splice(index, 0, item);
			itemCache[item] = true;
			vector.insert(index);
			vector.setItemSize(index, size);
			return item;
		}
		
		public function addAtPosition(item:*, position:int, size:int):*
		{
			return addAt(item, getIndexAt(position) + 1, size);
		}
		
		public function setSize(item:*, size:int):*
		{
			const i:int = getIndex(item);
			
			if(i == -1) return add(item, size);
			
			return setSizeAt(i, size);
		}
		
		public function setSizeAt(index:int, size:int):*
		{
			const item:* = getItemAtIndex(index);
			
			if(!(item || item in itemCache))
				return item;
			
			vector.setItemSize(index, size);
			return item;
		}
		
		public function remove(item:*):*
		{
			return removeAt(getIndex(item));
		}
		
		public function removeAt(index:int):*
		{
			const item:* = getItemAtIndex(index);
			
			if(!(item || item in itemCache))
				return item;
			
			indexCache.splice(index, 1);
			vector.remove(index);
			delete itemCache[item];
			return item;
		}
		
		public function removeAtPosition(position:int):*
		{
			return removeAt(getIndex(getItemAtPosition(position)));
		}
		
		public function getStart(item:*):int
		{
			return vector.start(getIndex(item));
		}
		
		public function getEnd(item:*):int
		{
			return vector.end(getIndex(item));
		}
		
		public function getSize(item:*):int
		{
			return vector.getItemSize(getIndex(item));
		}
		
		public function getIndex(item:*):int
		{
			return indexCache.indexOf(item);
		}
		
		public function getIndexAt(position:int):int
		{
			return vector.indexOf(position);
		}
		
		public function getItemAtIndex(index:int):*
		{
			return indexCache[index];
		}
		
		public function getItemAtPosition(position:int):*
		{
			return getItemAtIndex(getIndexAt(position));
		}
		
		public function slice(startPosition:int, endPosition:int):Array {
			
			startPosition = Math.min(Math.max(0, startPosition), size - 1);
			endPosition = Math.min(Math.max(0, endPosition), size - 1);
			
			const start:int = Math.max(Math.min(getIndexAt(startPosition), length), 0);
			const end:int = Math.max(Math.min(getIndexAt(endPosition), length), 0);
			
			return (start > end) ? 
				indexCache.slice(end, start + 1) :
				indexCache.slice(start, end + 1);
		}
	}
}

// This is a modified version of the 
// spark.layouts.supportClasses.LinearLayoutVector class from the Flex 4 
// framework. The dependencies on Flex 4 have been removed, and it has been 
// modified for general use.
/**
 * A sparse array of sizes that represent items in a dimension.
 *
 * Provides efficient support for finding the cumulative distance to
 * the start/end of an item along the axis, and similarly for finding the
 * index of the item at a particular distance.
 *
 * Default size is used for items whose size hasn't been specified.
 *
 * @langversion 3.0
 * @playerversion Flash 10
 * @playerversion AIR 1.5
 * @productversion Flex 4
 */
internal final class SparseArray
{
	// Assumption: vector elements (sizes) will typically be set in
	// small ranges that reflect localized scrolling.  Allocate vector
	// elements in blocks of BLOCK_SIZE, which must be a power of 2.
	// BLOCK_SHIFT is the power of 2 and BLOCK_MASK masks off as many 
	// low order bits.  The blockTable contains all of the allocated 
	// blocks and has length/BLOCK_SIZE elements which are allocated lazily.
	internal static const BLOCK_SIZE:uint = 128;
	internal static const BLOCK_SHIFT:uint = 7;
	internal static const BLOCK_MASK:uint = 0x7F;
	
	private const blockTable:Vector.<Block> = new Vector.<Block>(0, false);
	
	// Sorted Vector of intervals for the pending removes, in descending order, 
	// for example [7, 5, 3, 1] for the removes at 7, 6, 5, 3, 2, 1
	private var pendingRemoves:Vector.<int> = null;
	
	// Sorted Vector of intervals for the pending inserts, in ascending order, 
	// for example [1, 3, 5, 7] for the inserts at 1, 2, 3, 5, 6, 7
	private var pendingInserts:Vector.<int> = null;
	
	// What the length will be after any pending changes are flushed.
	private var pendingLength:int = -1;
	
	public function SparseArray()
	{
		super();
	}
	
	
	//--------------------------------------------------------------------------
	//
	//  Properties
	//
	//--------------------------------------------------------------------------
	
	
	//----------------------------------
	//  length
	//----------------------------------
	
	private var _length:uint = 0;
	
	/**
	 * The number of item size valued elements.
	 *
	 * @default 0
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function get length():uint
	{
		return pendingLength == -1 ? _length : pendingLength;
	}
	
	/**
	 * @private
	 */
	public function set length(value:uint):void
	{
		flushPendingChanges();
		setLength(value);
	}
	
	/**
	 * @private
	 * Grows or truncates the vector to be the specified newLength.
	 * When truncating, releases empty blocks and sets to NaN any values
	 * in the last block beyond the newLength.
	 */
	private function setLength(newLength:uint):void
	{
		if(newLength < _length)
		{
			// Clear any remaining non-NaN values in the last block
			var blockIndex:uint = newLength >> BLOCK_SHIFT;
			var endIndex:int = Math.min(blockIndex * BLOCK_SIZE + BLOCK_SIZE, _length) - 1;
			clearInterval(newLength, endIndex);
		}
		
		_length = newLength;
		
		// update the table
		var partialBlock:uint = ((_length & BLOCK_MASK) == 0) ? 0 : 1;
		blockTable.length = (_length >> BLOCK_SHIFT) + partialBlock;
	}
	
	//----------------------------------
	//  defaultSize
	//----------------------------------
	
	private var _defaultSize:Number = 0;
	
	/**
	 * The size of items whose size was not specified with setItemSize.
	 *
	 * @default 0
	 * @see #cacheDimensions
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function get defaultSize():Number
	{
		return _defaultSize;
	}
	
	/**
	 * @private
	 */
	public function set defaultSize(value:Number):void
	{
		_defaultSize = value;
	}
	
	//----------------------------------
	//  axisOffset
	//----------------------------------
	
	private var _axisOffset:Number = 0;
	
	/**
	 * The offset of the first item from the origin in the majorAxis
	 * direction. This is useful when implementing padding,
	 * in addition to gaps, for virtual layouts.
	 *
	 * @see #gap
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function get axisOffset():Number
	{
		return _axisOffset;
	}
	
	/**
	 * @private
	 */
	public function set axisOffset(value:Number):void
	{
		_axisOffset = value;
	}
	
	//----------------------------------
	//  gap
	//----------------------------------
	
	private var _gap:Number = 0;
	
	/**
	 * The distance between items.
	 *
	 * @default 0
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function get gap():Number
	{
		return _gap;
	}
	
	/**
	 * @private
	 */
	public function set gap(value:Number):void
	{
		_gap = value;
	}
	
	//--------------------------------------------------------------------------
	//
	//  Methods
	//
	//--------------------------------------------------------------------------
	
	/**
	 * Return the size of the item at index.  If no size was ever
	 * specified then then the defaultSize is returned.
	 *
	 * @param index The item's index.
	 * @see defaultSize
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function getItemSize(index:uint):Number
	{
		flushPendingChanges();
		
		var block:Block = blockTable[index >> BLOCK_SHIFT];
		if(block)
		{
			var value:Number = block.sizes[index & BLOCK_MASK];
			return (isNaN(value)) ? _defaultSize : value;
		}
		else
			return _defaultSize;
	}
	
	/**
	 * Set the size of the item at index.   If an index is
	 * set to <code>NaN</code> then subsequent calls to get
	 * will return the defaultSize.
	 *
	 * @param index The item's index.
	 * @param value The item's size.
	 * @see defaultSize
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function setItemSize(index:uint, value:Number):void
	{
		flushPendingChanges();
		
		if(index >= length)
			throw new Error("Invalid index and all that.");
		
		var blockIndex:uint = index >> BLOCK_SHIFT;
		var block:Block = blockTable[blockIndex];
		if(!block)
			block = blockTable[blockIndex] = new Block();
		
		var sizesIndex:uint = index & BLOCK_MASK;
		var sizes:Vector.<Number> = block.sizes;
		var oldValue:Number = sizes[sizesIndex];
		if(oldValue == value)
			return;
		
		if(isNaN(oldValue))
		{
			block.defaultCount -= 1;
			block.sizesSum += value;
		}
		else if(isNaN(value))
		{
			block.defaultCount += 1;
			block.sizesSum -= oldValue;
		}
		else
			block.sizesSum += value - oldValue;
		
		sizes[sizesIndex] = value;
	}
	
	/**
	 * Make room for a new item at index by shifting all of the sizes
	 * one position to the right, beginning with startIndex.
	 *
	 * The value at index will be NaN.
	 *
	 * This is similar to array.splice(index, 0, NaN).
	 *
	 * @param index The position of the new NaN size item.
	 */
	public function insert(index:uint):void
	{
		// We don't support interleaved pending inserts and removes
		if(pendingRemoves)
			flushPendingChanges();
		
		if(pendingInserts)
		{
			// Update the last interval or add a new one?
			var lastIndex:int = pendingInserts.length - 1;
			var intervalEnd:int = pendingInserts[lastIndex];
			
			if(index == intervalEnd + 1)
			{
				// Extend the end of the interval
				pendingInserts[lastIndex] = index;
			}
			else if(index > intervalEnd)
			{
				// New interval
				pendingInserts.push(index);
				pendingInserts.push(index);
			}
			else
			{
				// We can't support pending inserts that are not ascending
				flushPendingChanges();
			}
		}
		
		pendingLength = Math.max(length + 1, index + 1);
		
		if(!pendingInserts)
		{
			pendingInserts = new Vector.<int>();
			pendingInserts.push(index);
			pendingInserts.push(index);
		}
	}
	
	/**
	 * Remove index by shifting all of the sizes one position to the left,
	 * begining with index+1.
	 *
	 * This is similar to array.splice(index, 1).
	 *
	 * @param index The position to be removed.
	 */
	public function remove(index:uint):void
	{
		// We don't support interleaved pending inserts and removes
		if(pendingInserts)
			flushPendingChanges();
		
		// length getter takes into account pending inserts/removes but doesn't flush
		if(index >= length)
			throw new Error("Invalid index and all that.");
		
		if(pendingRemoves)
		{
			// Update the last interval or add a new one?
			var lastIndex:int = pendingRemoves.length - 1;
			var intervalStart:int = pendingRemoves[lastIndex];
			
			if(index == intervalStart - 1)
			{
				// Extend the start of the interval
				pendingRemoves[lastIndex] = index;
			}
			else if(index < intervalStart)
			{
				// New interval
				pendingRemoves.push(index);
				pendingRemoves.push(index);
			}
			else
			{
				// We can't support pending removes that are not descending
				flushPendingChanges();
			}
		}
		
		pendingLength = (pendingLength == -1) ? length - 1 : pendingLength - 1;
		
		if(!pendingRemoves)
		{
			pendingRemoves = new Vector.<int>();
			pendingRemoves.push(index);
			pendingRemoves.push(index);
		}
	}
	
	/**
	 * @private
	 * Returns true when all sizes in the specified interval for the block are NaN
	 */
	private function isIntervalClear(block:Block, index:int, count:int):Boolean
	{
		var sizesSrc:Vector.<Number> = block.sizes;
		for(var i:int = 0; i < count; i++)
		{
			if(!isNaN(sizesSrc[index + i]))
				return true;
		}
		return false;
	}
	
	/**
	 * @private
	 * Copies elements between blocks. Indices relative to the blocks.
	 * If srcBlock is null, then it fills the destination with NaNs.
	 * The case of srcBlock == dstBlock is also supported.
	 * The caller must ensure that count is within range.
	 */
	private function inBlockCopy(dstBlock:Block, dstIndexStart:int, srcBlock:Block, srcIndexStart:int, count:int):void
	{
		var ascending:Boolean = dstIndexStart < srcIndexStart;
		
		var srcIndex:int = ascending ? srcIndexStart : srcIndexStart + count - 1;
		var dstIndex:int = ascending ? dstIndexStart : dstIndexStart + count - 1;
		var increment:int = ascending ? +1 : -1;
		
		var dstSizes:Vector.<Number> = dstBlock.sizes;
		var srcSizes:Vector.<Number> = srcBlock ? srcBlock.sizes : null;
		var dstValue:Number = NaN;
		var srcValue:Number = NaN;
		var sizesSumDelta:Number = 0; // How much the destination sizesSum will change 
		var defaultCountDelta:int = 0; // How much the destination defaultCount will change
		
		while(count > 0)
		{
			if(srcSizes)
				srcValue = srcSizes[srcIndex];
			dstValue = dstSizes[dstIndex];
			
			// Are the values different?
			if(!(srcValue === dstValue)) // Triple '=' to handle NaN comparison
			{
				// Are we removing a default size or a chached size?
				if(isNaN(dstValue))
					defaultCountDelta--;
				else
					sizesSumDelta -= dstValue;
				
				// Are we adding a default size or a cached size?
				if(isNaN(srcValue))
					defaultCountDelta++;
				else
					sizesSumDelta += srcValue;
				
				dstSizes[dstIndex] = srcValue;
			}
			
			srcIndex += increment;
			dstIndex += increment;
			count--;
		}
		
		dstBlock.sizesSum += sizesSumDelta;
		dstBlock.defaultCount += defaultCountDelta;
	}
	
	/**
	 * @private
	 * Copies 'count' elements from dstIndex to srcIndex.
	 * Safe for overlapping source and destination intervals.
	 * If any blocks are left full of NaNs, they will be deallcated.
	 */
	private function copyInterval(dstIndex:int, srcIndex:int, count:int):void
	{
		var ascending:Boolean = dstIndex < srcIndex;
		if(!ascending)
		{
			dstIndex += count - 1;
			srcIndex += count - 1;
		}
		
		while(count > 0)
		{
			// Figure out destination block
			var dstBlockIndex:uint = dstIndex >> BLOCK_SHIFT;
			var dstSizesIndex:uint = dstIndex & BLOCK_MASK;
			var dstBlock:Block = blockTable[dstBlockIndex];
			
			// Figure out source block
			var srcBlockIndex:uint = srcIndex >> BLOCK_SHIFT;
			var srcSizesIndex:uint = srcIndex & BLOCK_MASK;
			var srcBlock:Block = blockTable[srcBlockIndex];
			
			// Figure out number of elements to copy
			var copyCount:int;
			if(ascending)
				copyCount = Math.min(BLOCK_SIZE - dstSizesIndex, BLOCK_SIZE - srcSizesIndex);
			else
				copyCount = 1 + Math.min(dstSizesIndex, srcSizesIndex);
			copyCount = Math.min(copyCount, count);
			
			// Figure out the start index for each block
			var dstStartIndex:int = ascending ? dstSizesIndex : dstSizesIndex - copyCount + 1;
			var srcStartIndex:int = ascending ? srcSizesIndex : srcSizesIndex - copyCount + 1;
			
			// Check whether a destination block needs to be allocated.
			// Allocate only if there are non-default values to be copied from the source. 
			if(srcBlock && !dstBlock &&
				isIntervalClear(srcBlock, srcStartIndex, copyCount))
			{
				dstBlock = new Block();
				blockTable[dstBlockIndex] = dstBlock;
			}
			
			// Copy to non-null dstBlock, srcBlock can be null
			if(dstBlock)
			{
				inBlockCopy(dstBlock, dstStartIndex, srcBlock, srcStartIndex, copyCount);
				
				// If this is the last time we're visiting this block, and it contains
				// only NaNs, then remove it
				if(dstBlock.defaultCount == BLOCK_SIZE)
				{
					var blockEndReached:Boolean = ascending ? (dstStartIndex + copyCount == BLOCK_SIZE) :
						(dstStartIndex == 0);
					if(blockEndReached || count == copyCount)
						blockTable[dstBlockIndex] = null;
				}
			}
			
			dstIndex += ascending ? copyCount : -copyCount;
			srcIndex += ascending ? copyCount : -copyCount;
			count -= copyCount;
		}
	}
	
	/**
	 * @private
	 * Sets all elements within the specified interval to NaN (both ends inclusive).
	 * Releases empty blocks.
	 */
	private function clearInterval(start:int, end:int):void
	{
		while(start <= end)
		{
			// Figure our destination block
			var blockIndex:uint = start >> BLOCK_SHIFT;
			var sizesIndex:uint = start & BLOCK_MASK;
			var block:Block = blockTable[blockIndex];
			
			// Figure out number of elements to clear in this iteration
			// Make sure we don't clear more items than requested
			var clearCount:int = BLOCK_SIZE - sizesIndex;
			clearCount = Math.min(clearCount, end - start + 1);
			
			if(block)
			{
				if(clearCount == BLOCK_SIZE)
					blockTable[blockIndex] = null;
				else
				{
					// Copying from null source block is equivalent of clearing the destination block
					inBlockCopy(block, sizesIndex, null /*srcBlock*/, 0, clearCount);
					
					// If the blockDst contains only default sizes, then remove the block
					if(block.defaultCount == BLOCK_SIZE)
						blockTable[blockIndex] = null;
				}
			}
			
			start += clearCount;
		}
	}
	
	/**
	 * @private
	 * Removes the elements designated by the intervals and truncates
	 * the LinearLayoutVector to the new length.
	 * 'intervals' is a Vector of descending intervals [7, 5, 3, 1]
	 */
	private function removeIntervals(intervals:Vector.<int>):void
	{
		var intervalsCount:int = intervals.length;
		if(intervalsCount == 0)
			return;
		
		// Adding final nextIntervalStart value (see below).
		intervals.reverse(); // turn into ascending, for example [7, 5, 3, 1] --> [1, 3, 5, 7]
		intervals.push(length);
		
		// Move the elements
		var dstStart:int = intervals[0];
		var srcStart:int;
		var count:int;
		var i:int = 0;
		do
		{
			var intervalEnd:int = intervals[i + 1];
			var nextIntervalStart:int = intervals[i + 2]
			i += 2;
			
			// Start copy from after the end of current interval
			srcStart = intervalEnd + 1;
			
			// copy all elements up to the start of the next interval.
			count = nextIntervalStart - srcStart;
			
			copyInterval(dstStart, srcStart, count);
			dstStart += count;
		} while(i < intervalsCount)
		
		// Truncate the excess elements.
		setLength(dstStart);
	}
	
	/**
	 * @private
	 * Increases the length and inserts NaN values for the elements designated by the intervals.
	 * 'intervals' is a Vector of ascending intervals [1, 3, 5, 7]
	 */
	private function insertIntervals(intervals:Vector.<int>, newLength:int):void
	{
		var intervalsCount:int = intervals.length;
		if(intervalsCount == 0)
			return;
		
		// Allocate enough space for the insertions, all the elements
		// allocated are NaN by default.
		var oldLength:int = length;
		setLength(newLength);
		
		var srcEnd:int = oldLength - 1;
		var dstEnd:int = newLength - 1;
		var i:int = intervalsCount - 2;
		while(i >= 0)
		{
			// Find current interval
			var intervalStart:int = intervals[i];
			var intervalEnd:int = intervals[i + 1];
			i -= 2;
			
			// Start after the current interval 
			var dstStart:int = intervalEnd + 1;
			var copyCount:int = dstEnd - dstStart + 1;
			var srcStart:int = srcEnd - copyCount + 1;
			
			copyInterval(dstStart, srcStart, copyCount);
			dstStart -= copyCount;
			dstEnd = intervalStart - 1;
			
			// Fill in with default NaN values after the copy
			clearInterval(intervalStart, intervalEnd);
		}
	}
	
	/**
	 * @private
	 * Processes any pending removes or pending inserts.
	 */
	private function flushPendingChanges():void
	{
		var intervals:Vector.<int>;
		if(pendingRemoves)
		{
			intervals = pendingRemoves;
			pendingRemoves = null;
			pendingLength = -1;
			removeIntervals(intervals);
		}
		else if(pendingInserts)
		{
			intervals = pendingInserts;
			var newLength:int = pendingLength;
			pendingInserts = null;
			pendingLength = -1;
			insertIntervals(intervals, newLength);
		}
	}
	
	/**
	 * The cumulative distance to the start of the item at index, including
	 * the gaps between items and the axisOffset.
	 *
	 * The value of start(0) is axisOffset.
	 *
	 * Equivalent to:
	 * <pre>
	 * var distance:Number = axisOffset;
	 * for (var i:int = 0; i &lt; index; i++)
	 *     distance += get(i);
	 * return distance + (gap * index);
	 * </pre>
	 *
	 * The actual implementation is relatively efficient.
	 *
	 * @param index The item's index.
	 * @see #end
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function start(index:uint):Number
	{
		flushPendingChanges();
		
		if((_length == 0) || (index == 0))
			return axisOffset;
		
		if(index >= _length)
			throw new Error("Invalid index and all that.");
		
		var distance:Number = axisOffset;
		var blockIndex:uint = index >> BLOCK_SHIFT;
		for(var i:int = 0; i < blockIndex; i++)
		{
			var block:Block = blockTable[i];
			if(block)
				distance += block.sizesSum + (block.defaultCount * _defaultSize);
			else
				distance += BLOCK_SIZE * _defaultSize;
		}
		var lastBlock:Block = blockTable[blockIndex];
		var lastBlockOffset:uint = index & ~BLOCK_MASK;
		var lastBlockLength:uint = index - lastBlockOffset;
		if(lastBlock)
		{
			var sizes:Vector.<Number> = lastBlock.sizes;
			for(i = 0; i < lastBlockLength; i++)
			{
				var size:Number = sizes[i];
				distance += (isNaN(size)) ? _defaultSize : size;
			}
		}
		else
			distance += _defaultSize * lastBlockLength;
		distance += index * gap;
		return distance;
	}
	
	/**
	 * The cumulative distance to the end of the item at index, including
	 * the gaps between items.
	 *
	 * If <code>index &lt;(length-1)</code> then the value of this
	 * function is defined as:
	 * <code>start(index) + get(index)</code>.
	 *
	 * @param index The item's index.
	 * @see #start
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function end(index:uint):Number
	{
		flushPendingChanges();
		return start(index) + getItemSize(index);
	}
	
	/**
	 * Returns the index of the item that overlaps the specified distance.
	 *
	 * The item at index <code>i</code> overlaps a distance value
	 * if <code>start(i) &lt;= distance &lt; end(i)</code>.
	 *
	 * If no such item exists, -1 is returned.
	 *
	 * @langversion 3.0
	 * @playerversion Flash 10
	 * @playerversion AIR 1.5
	 * @productversion Flex 4
	 */
	public function indexOf(distance:Number):int
	{
		flushPendingChanges();
		var index:int = indexOfInternal(distance);
		return (index >= _length) ? -1 : index;
	}
	
	private function indexOfInternal(distance:Number):int
	{
		if((_length == 0) || (distance < 0))
			return -1;
		
		// The area of the first item includes the axisOffset
		var curDistance:Number = axisOffset;
		if(distance < curDistance)
			return 0;
		
		var index:int = -1;
		var block:Block = null;
		var blockGap:Number = _gap * BLOCK_SIZE;
		
		// Find the block that contains distance and the index of its
		// first element
		for(var blockIndex:uint = 0; blockIndex < blockTable.length; blockIndex++)
		{
			block = blockTable[blockIndex];
			var blockDistance:Number = blockGap;
			if(block)
				blockDistance += block.sizesSum + (block.defaultCount * _defaultSize);
			else
				blockDistance += BLOCK_SIZE * _defaultSize;
			if((distance == curDistance) ||
				((distance >= curDistance) && (distance < (curDistance + blockDistance))))
			{
				index = blockIndex << BLOCK_SHIFT;
				break;
			}
			curDistance += blockDistance;
		}
		
		if((index == -1) || (distance == curDistance))
			return index;
		
		// At this point index corresponds to the first item in this block
		if(block)
		{
			// Find the item that contains distance and return its index
			var sizes:Vector.<Number> = block.sizes;
			for(var i:int = 0; i < BLOCK_SIZE - 1; i++)
			{
				var size:Number = sizes[i];
				curDistance += _gap + (isNaN(size) ? _defaultSize : size);
				if(curDistance > distance)
					return index + i;
			}
			// TBD special-case for the very last index
			return index + BLOCK_SIZE - 1;
		}
		else
		{
			return index + Math.floor(Number(distance - curDistance) / Number(_defaultSize + _gap));
		}
	}
	
	/**
	 * Clear all cached state, reset length to zero.
	 */
	public function clear():void
	{
		// Discard any pending changes, before setting the length
		// otherwise the length setter will commit the changes.
		pendingRemoves = null;
		pendingInserts = null;
		pendingLength = -1;
		
		length = 0; // clears the BlockTable as well
	}
	
	public function toString():String
	{
		return "LinearLayoutVector{" +
			"length=" + _length +
			" [blocks=" + blockTable.length + "]" +
			" gap=" + _gap +
			" defaultSize=" + _defaultSize +
			" pendingRemoves=" + (pendingRemoves ? pendingRemoves.length : 0) +
			" pendingInserts=" + (pendingInserts ? pendingInserts.length : 0) +
			"}";
	}
}

/**
 * @private
 * A SparseArray block of layout element heights or widths.
 *
 * Total "distance" for a Block is: sizesSum + (defaultCount * distanceVector.default).
 *
 * @langversion 3.0
 * @playerversion Flash 10
 * @playerversion AIR 1.5
 * @productversion Flex 4
 */
internal final class Block
{
	internal const sizes:Vector.<Number> = new Vector.<Number>(BLOCK_SIZE, true);
	internal var sizesSum:Number = 0;
	internal var defaultCount:uint = BLOCK_SIZE;
	
	public function Block()
	{
		super();
		for(var i:int = 0; i < BLOCK_SIZE; i += 1)
			sizes[i] = NaN;
	}
	
	internal static const BLOCK_SIZE:uint = 128;
}