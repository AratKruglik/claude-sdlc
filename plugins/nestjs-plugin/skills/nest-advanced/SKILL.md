---
name: nest-advanced
description: |
  GraphQL, WebSockets, and microservices patterns for NestJS. Apply only when the relevant package is in dependencies (`@nestjs/graphql`, `@nestjs/websockets`, `@nestjs/microservices`). Each section is orientation, not exhaustive — defer to NestJS docs for deep dives.

  Use this skill to:
  - Wire a GraphQL resolver (code-first) with class-validator inputs.
  - Build a WebSocket gateway with auth and room management.
  - Set up a microservice transport (TCP/RabbitMQ/NATS/Redis/Kafka) and message handlers.

  Do NOT use this skill for:
  - REST controllers (see nest-conventions + decorator-patterns).
  - ORM (see nest-data-layer).
  - Auth strategies (see security-analyst phase guidance).
user-invocable: false
paths: ["src/**/*.ts"]
---

# NestJS Advanced Surfaces

This skill covers the three advanced surfaces NestJS supports beyond REST. Each is opt-in via package presence — do not introduce these surfaces speculatively.

## GraphQL (`@nestjs/graphql`)

### Module setup (code-first, modern default)

```ts
import { GraphQLModule } from '@nestjs/graphql';
import { ApolloDriver, ApolloDriverConfig } from '@nestjs/apollo';

@Module({
  imports: [
    GraphQLModule.forRoot<ApolloDriverConfig>({
      driver: ApolloDriver,
      autoSchemaFile: 'schema.gql',         // or `true` for in-memory
      sortSchema: true,
      playground: process.env.NODE_ENV !== 'production',
      context: ({ req }) => ({ req }),
    }),
  ],
})
export class AppModule {}
```

### ObjectType (return types)

```ts
@ObjectType()
export class User {
  @Field(() => ID)
  id!: string;

  @Field()
  email!: string;

  @Field({ nullable: true })
  name?: string;

  @Field(() => [Order])
  orders!: Order[];
}
```

- `@Field()` — exposes the property; type inferred from TypeScript when possible.
- For arrays/non-primitive types, pass the explicit type: `@Field(() => [Order])`.
- `nullable: true` for optional fields; matches TS `?:` modifier.

### InputType (mutation inputs)

```ts
@InputType()
export class CreateUserInput {
  @Field()
  @IsEmail()
  email!: string;

  @Field()
  @MinLength(8)
  password!: string;
}
```

InputType + class-validator works alongside the global ValidationPipe for runtime checks.

### Resolver

```ts
@Resolver(() => User)
export class UsersResolver {
  constructor(private readonly users: UsersService) {}

  @Query(() => User, { nullable: true })
  user(@Args('id', { type: () => ID }) id: string) {
    return this.users.findById(id);
  }

  @Query(() => [User])
  users() {
    return this.users.findAll();
  }

  @Mutation(() => User)
  createUser(@Args('input') input: CreateUserInput) {
    return this.users.create(input);
  }

  @ResolveField(() => [Order])
  orders(@Parent() user: User) {
    return this.users.ordersByUserId(user.id);
  }
}
```

### Auth in GraphQL

`@UseGuards()` on resolvers and field resolvers. Use `GqlExecutionContext` in guards:

```ts
@Injectable()
export class GqlAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const ctx = GqlExecutionContext.create(context);
    const req = ctx.getContext().req;
    return !!req.user;
  }
}
```

For custom param decorators in GraphQL, use:

```ts
export const CurrentUser = createParamDecorator(
  (data: unknown, ctx: ExecutionContext) =>
    GqlExecutionContext.create(ctx).getContext().req.user,
);
```

### N+1 — DataLoader

```ts
@Injectable({ scope: Scope.REQUEST })
export class OrdersLoader {
  constructor(private readonly orders: OrdersService) {}

  readonly byUserId = new DataLoader<string, Order[]>(async (userIds) => {
    const orders = await this.orders.findByUserIds([...userIds]);
    return userIds.map((id) => orders.filter((o) => o.userId === id));
  });
}
```

Inject in resolver, use in `@ResolveField`. Avoids N+1 on `User.orders` across a list query.

### Federation pointer

`@nestjs/apollo` supports Apollo Federation v2 via `ApolloFederationDriver` + `@apollo/subgraph`. If the project uses federation (`@key` directives, multiple subgraphs), defer to NestJS Federation docs — patterns are stable but extensive.

### Schema-first variant

If the project uses schema-first (legacy or specific tooling), `.graphql` files drive types and `@Resolver` classes implement them via `@nestjs/graphql` codegen. Match what exists; don't migrate without BA approval.

## WebSockets (`@nestjs/websockets`)

### Gateway

```ts
import { WebSocketGateway, WebSocketServer, SubscribeMessage, MessageBody, ConnectedSocket, OnGatewayConnection, OnGatewayDisconnect } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';

@WebSocketGateway({
  cors: { origin: process.env.WS_ORIGIN ?? '*' },
  namespace: 'chat',
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  handleConnection(client: Socket) {
    // auth on connection — read token from handshake
  }

  handleDisconnect(client: Socket) {
    // cleanup
  }

  @SubscribeMessage('message')
  async onMessage(
    @MessageBody() payload: SendMessageDto,
    @ConnectedSocket() client: Socket,
  ): Promise<{ ok: true }> {
    this.server.to(payload.roomId).emit('message', { from: client.id, text: payload.text });
    return { ok: true };
  }
}
```

### Auth on connection

WebSocket auth is NOT covered by HTTP guards by default. Pattern:

1. Client sends token in `handshake.auth.token` (Socket.io) or `Sec-WebSocket-Protocol` (raw WS).
2. Gateway's `handleConnection(client)` validates synchronously; on failure, `client.disconnect(true)`.
3. Subsequent messages can rely on `client.data.user` populated at connect.

Or use `@UseGuards(WsJwtGuard)` per `@SubscribeMessage` — guard implements `canActivate` reading from socket handshake.

### Room management

```ts
client.join(`room:${roomId}`);
client.leave(`room:${roomId}`);
this.server.to(`room:${roomId}`).emit('event', payload);
```

Rooms are cheap; cleanup happens automatically on disconnect.

### Validation

DTOs work the same — global ValidationPipe applies if enabled at app level. For Socket.io, payload arrives as parsed JSON; class-transformer + class-validator validate normally.

### Adapters

`@nestjs/platform-socket.io` is the default. For raw `ws`, install `@nestjs/platform-ws` and `app.useWebSocketAdapter(new WsAdapter(app))`. For Redis-backed pub/sub across instances, install `@socket.io/redis-adapter` and configure in `IoAdapter` subclass.

## Microservices (`@nestjs/microservices`)

### Transports

| Transport | Use case |
|---|---|
| `Transport.TCP` | Simple node-to-node, no broker |
| `Transport.RMQ` (RabbitMQ) | Reliable queues, work distribution |
| `Transport.NATS` | High-throughput, lightweight messaging |
| `Transport.REDIS` | Pub/sub, simple event broadcasting |
| `Transport.KAFKA` | Event sourcing, log-based |
| `Transport.MQTT` | IoT |
| `Transport.GRPC` | Strongly-typed RPC, polyglot services |

### Hybrid app (HTTP + microservice)

```ts
// src/main.ts
async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.connectMicroservice<MicroserviceOptions>({
    transport: Transport.RMQ,
    options: {
      urls: [process.env.RABBITMQ_URL!],
      queue: 'orders_queue',
      queueOptions: { durable: true },
      prefetchCount: 1,
    },
  });

  await app.startAllMicroservices();
  await app.listen(3000);
}
```

### Standalone microservice

```ts
async function bootstrap() {
  const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
    transport: Transport.NATS,
    options: { servers: ['nats://localhost:4222'] },
  });
  await app.listen();
}
```

### Patterns

```ts
// request-response (returns)
@MessagePattern({ cmd: 'find_user' })
findUser(@Payload() dto: FindUserDto, @Ctx() context: RmqContext) {
  return this.users.findById(dto.id);
}

// fire-and-forget event
@EventPattern('order.placed')
async handleOrderPlaced(@Payload() event: OrderPlacedEvent) {
  await this.email.sendOrderConfirmation(event);
}
```

### Calling microservices from a service

```ts
@Injectable()
export class OrdersService {
  constructor(@Inject('USERS_SERVICE') private readonly usersClient: ClientProxy) {}

  async createOrder(userId: string, items: OrderItem[]) {
    const user = await firstValueFrom(this.usersClient.send({ cmd: 'find_user' }, { id: userId }));
    // ... use user
    this.usersClient.emit('order.placed', { userId, items });
  }
}
```

Register the client in module `providers`:

```ts
@Module({
  imports: [
    ClientsModule.register([
      {
        name: 'USERS_SERVICE',
        transport: Transport.RMQ,
        options: { urls: [process.env.RABBITMQ_URL!], queue: 'users_queue' },
      },
    ]),
  ],
})
```

### Acknowledgement and retries (RabbitMQ)

By default RabbitMQ auto-acks. For retry-safe handling, set `noAck: false` and ack manually:

```ts
@EventPattern('order.placed')
async handle(@Payload() data: any, @Ctx() ctx: RmqContext) {
  const channel = ctx.getChannelRef();
  const msg = ctx.getMessage();
  try {
    await this.process(data);
    channel.ack(msg);
  } catch {
    channel.nack(msg, false, true);     // requeue
  }
}
```

### Common pitfalls

- **Forgetting to start microservices** in hybrid app — `await app.startAllMicroservices()` BEFORE `app.listen()`.
- **Returning vs emitting** — `MessagePattern` for request-response; `EventPattern` for fire-and-forget. Mixing them causes hangs.
- **Serialization** — payloads must be JSON-serializable for most transports. Dates serialize as strings; class instances lose prototype.
- **Backpressure** in Kafka/RabbitMQ — set prefetch / max in-flight to avoid overwhelming consumers.
- **No global pipes by default in microservices** — apply `@UsePipes(new ValidationPipe())` per handler or via `app.useGlobalPipes()` on the microservice instance.

## Anti-patterns (all surfaces)

- ❌ Mixing GraphQL and REST for the same resource without a clear boundary.
- ❌ WebSocket auth via cookies only (no fallback for native clients).
- ❌ Microservice handlers blocking on long DB calls without backpressure.
- ❌ Treating GraphQL field resolvers as cheap when they trigger DB roundtrips (use DataLoader).
- ❌ Putting business logic in resolvers/gateways/handlers — always delegate to services.
