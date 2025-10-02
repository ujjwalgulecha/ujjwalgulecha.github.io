---
layout: post
title: "Improve your page load latency"
date: 2025-09-23 14:00:00 -0800
categories: [performance, systems, engineering]
tags: [performance-optimization, scalability, backend, distributed-systems, web-performance]
description: "Make your pages load faster through systematic performance optimization, going beyond basic caching to orchestrate a coherent high-performance system."
image: /assets/images/social-card.svg
---

At scale, every millisecond matters. When your application serves millions of users across diverse network conditions and devices, traditional performance advice falls short. After optimizing page load performance for systems handling **50M+ monthly requests**, I've learned that sustainable performance improvements require a fundamentally different approach than what most guides suggest.

This isn't about basic database indexing or adding Redis. We'll take a systematic look at the architecture decisions, measurement strategies, and mobile-specific patterns that separate high-performing backend services from the rest.

---

## The Real Performance Problem

Most performance discussions focus on individual techniques—caching, compression, database tuning. But at scale, the challenge isn't knowing these techniques; it's orchestrating them into a coherent system that remains fast under real-world conditions.

Consider this: reducing your P50 latency from 200ms to 150ms sounds great, but if your P99 jumps from 500ms to 2s because of cache stampedes, you've made the user experience worse for the users who matter most—those on the edge of your performance envelope.

**Real-world example**: Discord scaled individual servers from tens of thousands of concurrent users to approaching two million concurrent users in the past few years. Their biggest challenge wasn't individual slow queries—it was managing the quadratic scaling problem where fanout work grows exponentially with server size. With 100,000 people online, a single message becomes 10 billion notifications to deliver [[1]](https://discord.com/blog/maxjourney-pushing-discords-limits-with-a-million-plus-online-users-in-a-single-server).

---

## Step 1: Build Performance-First Observability

### What to Measure That Actually Matters

*"You can't improve what you can't measure."* – Often attributed to Peter Drucker. This is extremely important when you are solving latency issues. If you don't know what the breakdown of page load latency is, you will not be able to solve the problem effectively.

Always start with the user and how the user experiences things. In your case, it could be an actual person or it could be another microservice calling your endpoint.

### Add Observability at All Stages

1. **End-user to service** – Record the time from firing a request to getting a response back. Capture P50, P90, P99 and P999 latencies. Users complain about the tail (P99/P999), not the average. Google's "The Tail at Scale" paper is a must-read [[2]](https://research.google/pubs/the-tail-at-scale/).

   Measure not just latency, but also error budgets (SLOs from SRE practices [[3]](https://sre.google/sre-book/service-level-objectives/)). If 99.9% of requests need to be <200ms, observability should highlight where that budget is getting burned.

2. **Client-side latency** – Measure how much time it took to decode data, deserialize it, and render the UI. Should also segment performance by device type, network conditions, app version, and geographic region. A 200ms response time on WiFi is excellent; on 3G in rural areas, it might cause timeouts.

3. **Within your service** – Break down time taken for each component. If you have a DAG workflow, measure time per node, and identify the critical path. Distributed tracing (via OpenTelemetry or Jaeger) is key for microservices. For example, if one slow DB call in a DAG delays the entire critical path, tracing highlights it instantly.

4. **System-level metrics** – CPU utilization, memory usage, garbage collection, threads blocked, threads queued, disk I/O, and network bandwidth.

Tools like **OpenTelemetry**, **Datadog**, or **New Relic** can help set up structured observability pipelines. With this you can get an idea where the problem is - user device? Network? Database? server?

**Pro tip**: Set up error budgets alongside latency monitoring. If 99.9% of requests need to be under 200ms, your observability should highlight exactly where that budget is getting burned.

---

## Step 2: Systematic Optimization Strategies

### 1. Compression – Smaller Payloads, Faster Loads

Enable **Brotli compression** (preferred over Gzip on modern devices) to reduce payload size. But always experiment: compression and decompression cost CPU cycles, and for very small payloads it might not help.

- **Dynamic vs static compression**: Static for assets (JS, CSS, images), dynamic for JSON/HTML.
- **Skip already compressed formats**: JPEG, PNG, and MP4 don't benefit from recompression.

**Case study**: LinkedIn's adoption of Brotli reduced JSON payloads by ~14% on average [[4]](https://www.linkedin.com/blog/engineering/optimization/boosting-site-speed-using-brotli-compression).

### 2. Smart Pagination and Progressive Loading - Don't load everything at once

The first screen users see is critical. If it's slow, they bounce. Focus on above-the-fold prioritization—load only what's visible, fetch the rest later.

- **Cursor-based pagination** (more reliable than offset-based when data changes)
- **Skeleton UIs and shimmer loaders** (Facebook and YouTube use these to make waiting feel faster)
- **Progressive image loading** with placeholder blur effects

Remember: Pagination is as much about perception of speed as actual latency.

### 3. Caching - Fast but Requires Strategy

A great caching strategy can cut load times by orders of magnitude. A poor one can cause stale data, stampedes, or outages.

**Multi-layer approach**
- **L1 caching**: In-memory (fast but local)
- **L2 caching**: Distributed Redis/Memcached
- **CDN caching**: Geographic distribution with smart invalidation

**Advanced patterns**
- **Stale-while-revalidate**: Serve cached data immediately, refresh in background
- **Jittered TTLs**: Prevent cache stampedes when many keys expire simultaneously
- **Read-through vs write-through** strategies based on your consistency needs

**Case study**: How Facebook Scaled and Optimized for Massive Request Volumes [[5]](https://blog.bytebytego.com/p/how-facebook-served-billions-of-requests)

For a deep dive, see the **Caching Best Practices** guide from AWS [[6]](https://aws.amazon.com/caching/best-practices/)

### 4. Code Optimization – Hunt Down Inefficiencies

You might be surprised/not surprised how much inefficiency lies in production code.

- **Profile hot paths** using tools like `perf`, `py-spy`, `jvisualvm`.
- **Optimize parsing/serialization** (e.g., switch to `simdjson` for faster JSON parsing).
- **Avoid quadratic loops** and unnecessary allocations.
- **Use object pooling** where it helps with high churn objects.

Netflix, for example, optimized its JSON-to-UI rendering pipeline and **shaved 200ms off median latency** [[7]](https://netflixtechblog.com/seamlessly-swapping-the-api-backend-of-the-netflix-android-app-3d4317155187).

**Real-world example from production**: At DoorDash, we encountered a counterintuitive optimization case. A Kotlin service was processing multiple lists of objects (list1, list2, list3, list4, list5) that needed to be cross-referenced by identifiers to produce a final aggregated list.

The "obvious" optimization was converting lists to HashMaps for O(1) lookups instead of O(n) linear searches:

```kotlin
// Initial "obvious" optimization - but turned out to be slower
fun processOrdersOptimized(
    restaurants: List<Restaurant>,
    orders: List<Order>,
    drivers: List<Driver>,
    customers: List<Customer>,
    locations: List<Location>
): List<DeliveryInfo> {
    val restaurantMap = restaurants.associateBy { it.id }  // Hash computation bottleneck
    val driverMap = drivers.associateBy { it.id }          // Hash computation bottleneck
    val customerMap = customers.associateBy { it.id }      // Hash computation bottleneck
    val locationMap = locations.associateBy { it.id }     // Hash computation bottleneck

    return orders.map { order ->
        DeliveryInfo(
            restaurant = restaurantMap[order.restaurantId]!!,  // O(1) lookup
            driver = driverMap[order.driverId]!!,              // O(1) lookup
            customer = customerMap[order.customerId]!!,        // O(1) lookup
            location = locationMap[order.locationId]!!         // O(1) lookup
        )
    }
}

// What actually performed better - linear search on small lists
fun processOrdersFaster(
    restaurants: List<Restaurant>,
    orders: List<Order>,
    drivers: List<Driver>,
    customers: List<Customer>,
    locations: List<Location>
): List<DeliveryInfo> {
    return orders.map { order ->
        DeliveryInfo(
            restaurant = restaurants.first { it.id == order.restaurantId }, // O(n) but faster
            driver = drivers.first { it.id == order.driverId },             // O(n) but faster
            customer = customers.first { it.id == order.customerId },       // O(n) but faster
            location = locations.first { it.id == order.locationId }       // O(n) but faster
        )
    }
}
```

The issue? **Hash computation overhead**. These complex domain objects had expensive `hashCode()` implementations, and the CPU cost of computing hashes for map creation exceeded the benefit of O(1) lookups. With small list sizes (typically <50 items), linear search was significantly faster overall.

**Key takeaway**: Big O notation assumes operations have constant cost, but in reality, the "constant" matters enormously. Always profile real workloads—theoretical optimizations can become practical pessimizations.

### 5. Smart Parallelization

Parallelizing workloads can dramatically reduce latency when handling multiple independent dependencies. The key is doing it safely.

**What works:**
- Async/await patterns for I/O-bound operations
- Parallel processing of independent API calls
- Background job processing for non-critical tasks

**What to avoid**
- Over-parallelization that saturates database connection pools
- Missing backpressure controls that can overwhelm downstream services

### 6. Database Query Optimization – The Usual Suspect

Databases are frequently the bottleneck, but the solutions go beyond adding indexes.

- **Optimize for reads** – Design your schema and queries for read performance, even if writes become more complex.
- **Avoid N+1 queries** – Batch database requests whenever possible
- **Materialized views** – Precompute expensive query results
- **Sharding strategies** – By user ID (balanced load) or geography (latency reduction).

**Case study**: Instagram scaled feeds to billions of users by sharding Postgres across IDs [[8]](https://www.google.com/search?q=Instagram+Engineering+-+Scaling+Feeds+with+Postgres+Sharding&oq=Instagram+Engineering+-+Scaling+Feeds+with+Postgres+Sharding&gs_lcrp=EgZjaHJvbWUyBggAEEUYOTIHCAEQIRigATIHCAIQIRiPAtIBBzE5M2owajSoAgCwAgA&sourceid=chrome&ie=UTF-8).

**References**: Use the Index, Luke! [[9]](https://use-the-index-luke.com/), [Postgres Performance Tips] [[10]](https://www.postgresql.org/docs/current/performance-tips.html).

---

## Wrapping Up

### The Systematic Approach

1. **Measure comprehensively** - Set up observability across your entire stack
2. **Identify the biggest bottleneck** - Use data, not assumptions
3. **Apply targeted optimizations** - Focus on highest-impact changes first
4. **Measure the results** - Validate that your changes actually improved user experience
5. **Repeat** - Performance optimization is an ongoing process

### Success Metrics That Matter

Track both technical and business metrics:

- **Technical**: P99 latency reduction, error rate improvements, throughput increases
- **Business**: Bounce rate reduction, conversion rate improvements, user engagement increases

**Key insight**: A 100ms improvement in page load time can increase conversion rates by 1-2% for e-commerce sites. At scale, this translates to millions in revenue impact.

Performance optimization at scale is about **systems thinking**, not just individual optimizations. Start with comprehensive observability, then systematically address bottlenecks based on real user impact data.

As Jeff Dean from Google puts it: *"If you want your system to be fast, first make it correct. Then profile, measure, and optimize the hot spots."*

Whether you're building mobile apps, APIs, or distributed systems, the principles remain the same: **measure, experiment, optimize, and repeat**. The difference at scale is that every optimization needs to work harmoniously with all the others—and that's where the real engineering challenge lies.

---

**References:**

[1] [Discord Engineering Blog - Scaling Message Fanout](https://discord.com/blog/maxjourney-pushing-discords-limits-with-a-million-plus-online-users-in-a-single-server) <br>
[2] [Google Research - The Tail at Scale](https://research.google/pubs/the-tail-at-scale/) <br>
[3] [Google SRE Book - Service Level Objectives](https://sre.google/sre-book/service-level-objectives/) <br>
[4] [LinkedIn Engineering Blog - Adopting Brotli Compression](https://www.linkedin.com/blog/engineering/optimization/boosting-site-speed-using-brotli-compression) <br>
[5] [Facebook Engineering - Scaling and Optimizing for Request Volumes](https://blog.bytebytego.com/p/how-facebook-served-billions-of-requests) <br>
[6] [AWS Best Practices - Caching Strategies](https://aws.amazon.com/caching/best-practices/) <br>
[7] [Netflix Tech Blog - JSON-to-UI Pipeline Optimization](https://netflixtechblog.com/seamlessly-swapping-the-api-backend-of-the-netflix-android-app-3d4317155187) <br>
[8] [Instagram Engineering - Scaling Feeds with Postgres Sharding](https://www.google.com/search?q=Instagram+Engineering+-+Scaling+Feeds+with+Postgres+Sharding&oq=Instagram+Engineering+-+Scaling+Feeds+with+Postgres+Sharding&gs_lcrp=EgZjaHJvbWUyBggAEEUYOTIHCAEQIRigATIHCAIQIRiPAtIBBzE5M2owajSoAgCwAgA&sourceid=chrome&ie=UTF-8) <br>
[9] [Use the Index, Luke! - SQL Performance Explained](https://use-the-index-luke.com/) <br>
[10] [PostgreSQL Performance Tips - Official Documentation](https://www.postgresql.org/docs/current/performance-tips.html) <br>