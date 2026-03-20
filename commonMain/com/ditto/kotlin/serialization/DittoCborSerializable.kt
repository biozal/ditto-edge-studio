package com.ditto.kotlin.serialization

import com.ditto.internal.serialization.InternalDittoCborSerializable
import com.ditto.internal.serialization.attachment
import com.ditto.internal.serialization.attachmentOrNull
import com.ditto.internal.util.get
import com.ditto.internal.util.getValue
import com.ditto.kotlin.DittoAttachmentToken
import com.ditto.kotlin.error.DittoExceptionFactory
import com.ditto.kotlin.toFacade

public sealed class DittoCborSerializable {
    internal abstract val implementation: InternalDittoCborSerializable

    public val isNull: Boolean by ::implementation[InternalDittoCborSerializable::isNull]

    public operator fun get(key: String): DittoCborSerializable = implementation.get(key).toFacade()
    public operator fun get(index: Int): DittoCborSerializable = implementation.get(index).toFacade()

    public val attachmentToken: DittoAttachmentToken get() = implementation.attachment(DittoExceptionFactory).toFacade()
    public val attachmentTokenOrNull: DittoAttachmentToken?
        get() = implementation.attachmentOrNull(
            DittoExceptionFactory
        )?.toFacade()

    public val byteArray: ByteArray get() = implementation.getByteArray(DittoExceptionFactory)
    public val byteArrayOrNull: ByteArray? get() = implementation.getByteArrayOrNull(DittoExceptionFactory)
    public val nullableByteArray: ByteArray? get() = implementation.requireNullableByteArray(DittoExceptionFactory)

    public val uByteArray: UByteArray get() = implementation.getUByteArray(DittoExceptionFactory)
    public val uByteArrayOrNull: UByteArray? get() = implementation.getUByteArrayOrNull(DittoExceptionFactory)
    public val nullableUByteArray: UByteArray? get() = implementation.requireNullableUByteArray(DittoExceptionFactory)

    public val boolean: Boolean get() = implementation.getBoolean(DittoExceptionFactory)
    public val booleanOrNull: Boolean? get() = implementation.getBooleanOrNull(DittoExceptionFactory)
    public val nullableBoolean: Boolean? get() = implementation.requireNullableBoolean(DittoExceptionFactory)

    public val string: String get() = implementation.getString(DittoExceptionFactory)
    public val stringOrNull: String? get() = implementation.getStringOrNull(DittoExceptionFactory)
    public val nullableString: String? get() = implementation.requireNullableString(DittoExceptionFactory)

    public val byte: Byte get() = implementation.getByte(DittoExceptionFactory)
    public val byteOrNull: Byte? get() = implementation.getByteOrNull(DittoExceptionFactory)
    public val nullableByte: Byte? get() = implementation.requireNullableByte(DittoExceptionFactory)

    public val uByte: UByte get() = implementation.getUByte(DittoExceptionFactory)
    public val uByteOrNull: UByte? get() = implementation.getUByteOrNull(DittoExceptionFactory)
    public val nullableUByte: UByte? get() = implementation.requireNullableUByte(DittoExceptionFactory)

    public val short: Short get() = implementation.getShort(DittoExceptionFactory)
    public val shortOrNull: Short? get() = implementation.getShortOrNull(DittoExceptionFactory)
    public val nullableShort: Short? get() = implementation.requireNullableShort(DittoExceptionFactory)

    public val uShort: UShort get() = implementation.getUShort(DittoExceptionFactory)
    public val uShortOrNull: UShort? get() = implementation.getUShortOrNull(DittoExceptionFactory)
    public val nullableUShort: UShort? get() = implementation.requireNullableUShort(DittoExceptionFactory)

    public val int: Int get() = implementation.getInt(DittoExceptionFactory)
    public val intOrNull: Int? get() = implementation.getIntOrNull(DittoExceptionFactory)
    public val nullableInt: Int? get() = implementation.requireNullableInt(DittoExceptionFactory)

    public val uInt: UInt get() = implementation.getUInt(DittoExceptionFactory)
    public val uIntOrNull: UInt? get() = implementation.getUIntOrNull(DittoExceptionFactory)
    public val nullableUInt: UInt? get() = implementation.requireNullableUInt(DittoExceptionFactory)

    public val long: Long get() = implementation.getLong(DittoExceptionFactory)
    public val longOrNull: Long? get() = implementation.getLongOrNull(DittoExceptionFactory)
    public val nullableLong: Long? get() = implementation.requireNullableLong(DittoExceptionFactory)

    public val uLong: ULong get() = implementation.getULong(DittoExceptionFactory)
    public val uLongOrNull: ULong? get() = implementation.getULongOrNull(DittoExceptionFactory)
    public val nullableULong: ULong? get() = implementation.requireNullableULong(DittoExceptionFactory)

    public val float: Float get() = implementation.getFloat(DittoExceptionFactory)
    public val floatOrNull: Float? get() = implementation.getFloatOrNull(DittoExceptionFactory)
    public val nullableFloat: Float? get() = implementation.requireNullableFloat(DittoExceptionFactory)

    public val double: Double get() = implementation.getDouble(DittoExceptionFactory)
    public val doubleOrNull: Double? get() = implementation.getDoubleOrNull(DittoExceptionFactory)
    public val nullableDouble: Double? get() = implementation.requireNullableDouble(DittoExceptionFactory)

    public val dictionary: Dictionary get() = implementation.getDictionary(DittoExceptionFactory).toFacade()
    public val dictionaryOrNull: Dictionary?
        get() = implementation.getDictionaryOrNull(DittoExceptionFactory)?.toFacade()
    public val nullableDictionary: Dictionary?
        get() = implementation.requireNullableDictionary(DittoExceptionFactory)?.toFacade()

    public val list: ArrayValue get() = implementation.getList(DittoExceptionFactory).toFacade()
    public val listOrNull: ArrayValue? get() = implementation.getListOrNull(DittoExceptionFactory)?.toFacade()
    public val nullableList: ArrayValue? get() = implementation.requireNullableList(DittoExceptionFactory)?.toFacade()

    public val tagged: Tagged get() = implementation.getTagged(DittoExceptionFactory).toFacade()
    public val taggedOrNull: Tagged? get() = implementation.getTaggedOrNull(DittoExceptionFactory)?.toFacade()
    public val nullableTagged: Tagged? get() = implementation.requireNullableTagged(DittoExceptionFactory)?.toFacade()

    override fun equals(other: Any?): Boolean {
        if (other !is DittoCborSerializable) return false
        return implementation == other.implementation
    }

    override fun hashCode(): Int = implementation.hashCode()

    override fun toString(): String = implementation.toString()

    // Major type 0
    public class UnsignedInteger(
        override val implementation: InternalDittoCborSerializable.UnsignedInteger,
    ) : DittoCborSerializable() {
        public constructor(value: ULong) : this(InternalDittoCborSerializable.UnsignedInteger(value))
    }

    // Major type 1
    public class NegativeInteger(
        override val implementation: InternalDittoCborSerializable.NegativeInteger,
    ) : DittoCborSerializable() {
        public constructor(value: ULong) : this(InternalDittoCborSerializable.NegativeInteger(value))
    }

    // Major type 2
    public class ByteString(
        override val implementation: InternalDittoCborSerializable.ByteString,
    ) : DittoCborSerializable() {
        public constructor(value: UByteArray) : this(InternalDittoCborSerializable.ByteString(value))
    }

    // Major type 3
    public class Utf8String(
        override val implementation: InternalDittoCborSerializable.Utf8String,
    ) : DittoCborSerializable() {
        public constructor(value: String) : this(InternalDittoCborSerializable.Utf8String(value))
    }

    // Major type 4
    public class ArrayValue(
        override val implementation: InternalDittoCborSerializable.ArrayValue,
    ) : DittoCborSerializable(), List<DittoCborSerializable> {
        public constructor() : this(InternalDittoCborSerializable.ArrayValue(emptyList()))
        public constructor(list: List<DittoCborSerializable>) : this(
            InternalDittoCborSerializable.ArrayValue(
                list.map { it.toInternal() }
            )
        )

        public override val size: Int get() = implementation.size

        override fun isEmpty(): Boolean = implementation.isEmpty()

        override fun iterator(): Iterator<DittoCborSerializable> {
            val implementationIterator = implementation.iterator()
            return object: Iterator<DittoCborSerializable> {
                override fun hasNext(): Boolean = implementationIterator.hasNext()

                override fun next(): DittoCborSerializable = implementationIterator.next().toFacade()
            }
        }

        override fun listIterator(): ListIterator<DittoCborSerializable> =
            implementation.listIterator().toFacade()

        override fun listIterator(index: Int): ListIterator<DittoCborSerializable> =
            implementation.listIterator(index).toFacade()

        override fun subList(fromIndex: Int, toIndex: Int): List<DittoCborSerializable> =
            implementation.subList(fromIndex = fromIndex, toIndex = toIndex).map { it.toFacade() }

        override fun lastIndexOf(element: DittoCborSerializable): Int =
            implementation.lastIndexOf(element.implementation)

        override fun indexOf(element: DittoCborSerializable): Int =
            implementation.indexOf(element.implementation)

        override fun containsAll(elements: Collection<DittoCborSerializable>): Boolean =
            implementation.containsAll(elements.map { it.toInternal() })

        override fun contains(element: DittoCborSerializable): Boolean =
            implementation.contains(element.implementation)
    }

    // Major type 5
    public class Dictionary internal constructor(
        override val implementation: InternalDittoCborSerializable.Dictionary,
    ) : DittoCborSerializable(), Map<DittoCborSerializable, DittoCborSerializable> {
        public constructor() : this(InternalDittoCborSerializable.Dictionary(emptyMap()))
        public constructor(map: Map<DittoCborSerializable, DittoCborSerializable>) : this(
            InternalDittoCborSerializable.Dictionary(
                map.mapKeys { it.key.toInternal() }.mapValues { it.value.toInternal() }
            )
        )

        override val entries: Set<Map.Entry<DittoCborSerializable, DittoCborSerializable>>
            get() = implementation.entries.map { entry -> DictionaryEntry(entry) }.toSet()

        override val keys: Set<DittoCborSerializable>
            get() = implementation.keys.map { it.toFacade() }.toSet()

        override val size: Int
            get() = implementation.size

        override val values: Collection<DittoCborSerializable>
            get() = implementation.values.map { it.toFacade() }

        override fun isEmpty(): Boolean = implementation.isEmpty()

        override fun containsValue(value: DittoCborSerializable): Boolean =
            implementation.containsValue(value.implementation)

        override fun containsKey(key: DittoCborSerializable): Boolean =
            implementation.containsKey(key.implementation)

        override fun get(key: DittoCborSerializable): DittoCborSerializable? =
            implementation.get(key.implementation).toFacade()

        private class DictionaryEntry(
            val implementation: Map.Entry<InternalDittoCborSerializable, InternalDittoCborSerializable>
        ) : Map.Entry<DittoCborSerializable, DittoCborSerializable> {
            override val key: DittoCborSerializable
                get() = implementation.key.toFacade()
            override val value: DittoCborSerializable
                get() = implementation.value.toFacade()

            override fun hashCode(): Int = implementation.hashCode()

            override fun equals(other: Any?): Boolean {
                return if (other is DictionaryEntry) {
                    return other.implementation.equals(implementation)
                } else {
                    super.equals(other)
                }
            }
        }
    }

    // Major type 6
    public class Tagged(
        override val implementation: InternalDittoCborSerializable.Tagged,
    ) : DittoCborSerializable() {
        public constructor(tag: ULong, value: DittoCborSerializable) : this(
            InternalDittoCborSerializable.Tagged(tag, value.toInternal())
        )

        public val tag: ULong get() = implementation.tag
        public val value: DittoCborSerializable get() = implementation.value.toFacade()
    }

    // region Major type 7
    public class BooleanValue(
        override val implementation: InternalDittoCborSerializable.BooleanValue,
    ) : DittoCborSerializable() {
        public constructor(value: Boolean) : this(InternalDittoCborSerializable.BooleanValue(value))
    }

    public class NullValue internal constructor(
        override val implementation: InternalDittoCborSerializable.NullValue
    ) : DittoCborSerializable() {
        public constructor() : this(InternalDittoCborSerializable.NullValue)
    }

    public class FloatValue(
        override val implementation: InternalDittoCborSerializable.FloatValue
    ) : DittoCborSerializable() {
        public constructor(value: Float) : this(InternalDittoCborSerializable.FloatValue(value))
    }

    public class DoubleValue(
        override val implementation: InternalDittoCborSerializable.DoubleValue
    ) : DittoCborSerializable() {
        public constructor(value: Double) : this(InternalDittoCborSerializable.DoubleValue(value))
    }
}

internal fun InternalDittoCborSerializable.NullValue.toFacade() = DittoCborSerializable.NullValue(this)
internal fun InternalDittoCborSerializable.Dictionary.toFacade() = DittoCborSerializable.Dictionary(this)
internal fun InternalDittoCborSerializable.ArrayValue.toFacade() = DittoCborSerializable.ArrayValue(this)
internal fun InternalDittoCborSerializable.BooleanValue.toFacade() = DittoCborSerializable.BooleanValue(this)
internal fun InternalDittoCborSerializable.ByteString.toFacade() = DittoCborSerializable.ByteString(this)
internal fun InternalDittoCborSerializable.DoubleValue.toFacade() = DittoCborSerializable.DoubleValue(this)
internal fun InternalDittoCborSerializable.FloatValue.toFacade() = DittoCborSerializable.FloatValue(this)
internal fun InternalDittoCborSerializable.NegativeInteger.toFacade() = DittoCborSerializable.NegativeInteger(this)
internal fun InternalDittoCborSerializable.Tagged.toFacade() = DittoCborSerializable.Tagged(this)
internal fun InternalDittoCborSerializable.UnsignedInteger.toFacade() = DittoCborSerializable.UnsignedInteger(this)
internal fun InternalDittoCborSerializable.Utf8String.toFacade() = DittoCborSerializable.Utf8String(this)

internal fun InternalDittoCborSerializable.toFacade() = when (this) {
    is InternalDittoCborSerializable.NullValue -> toFacade()
    is InternalDittoCborSerializable.Dictionary -> toFacade()
    is InternalDittoCborSerializable.ArrayValue -> toFacade()
    is InternalDittoCborSerializable.BooleanValue -> toFacade()
    is InternalDittoCborSerializable.ByteString -> toFacade()
    is InternalDittoCborSerializable.DoubleValue -> toFacade()
    is InternalDittoCborSerializable.FloatValue -> toFacade()
    is InternalDittoCborSerializable.NegativeInteger -> toFacade()
    is InternalDittoCborSerializable.Tagged -> toFacade()
    is InternalDittoCborSerializable.UnsignedInteger -> toFacade()
    is InternalDittoCborSerializable.Utf8String -> toFacade()
}

internal fun DittoCborSerializable.NullValue.toInternal() = this.implementation
internal fun DittoCborSerializable.Dictionary.toInternal() = this.implementation
internal fun DittoCborSerializable.ArrayValue.toInternal() = this.implementation
internal fun DittoCborSerializable.BooleanValue.toInternal() = this.implementation
internal fun DittoCborSerializable.ByteString.toInternal() = this.implementation
internal fun DittoCborSerializable.DoubleValue.toInternal() = this.implementation
internal fun DittoCborSerializable.FloatValue.toInternal() = this.implementation
internal fun DittoCborSerializable.NegativeInteger.toInternal() = this.implementation
internal fun DittoCborSerializable.Tagged.toInternal() = this.implementation
internal fun DittoCborSerializable.UnsignedInteger.toInternal() = this.implementation
internal fun DittoCborSerializable.Utf8String.toInternal() = this.implementation

internal fun DittoCborSerializable.toInternal() = when (this) {
    is DittoCborSerializable.NullValue -> toInternal()
    is DittoCborSerializable.Dictionary -> toInternal()
    is DittoCborSerializable.ArrayValue -> toInternal()
    is DittoCborSerializable.BooleanValue -> toInternal()
    is DittoCborSerializable.ByteString -> toInternal()
    is DittoCborSerializable.DoubleValue -> toInternal()
    is DittoCborSerializable.FloatValue -> toInternal()
    is DittoCborSerializable.NegativeInteger -> toInternal()
    is DittoCborSerializable.Tagged -> toInternal()
    is DittoCborSerializable.UnsignedInteger -> toInternal()
    is DittoCborSerializable.Utf8String -> toInternal()
}

internal fun ListIterator<InternalDittoCborSerializable>.toFacade(): ListIterator<DittoCborSerializable> =
    object: ListIterator<DittoCborSerializable> {
        override fun hasNext(): Boolean = this@toFacade.hasNext()

        override fun hasPrevious(): Boolean = this@toFacade.hasPrevious()

        override fun next(): DittoCborSerializable = this@toFacade.next().toFacade()

        override fun nextIndex(): Int = this@toFacade.nextIndex()

        override fun previous(): DittoCborSerializable = this@toFacade.previous().toFacade()

        override fun previousIndex(): Int = this@toFacade.previousIndex()
    }
